/* spr_test.c — bare-metal bring-up for spr_accel_axi + vector_player (ZedBoard)
 * Expected UART output per frame: p_min=639 den=121834 fwhm=30 fwhm_ctr=639 PASS
 * NOTE: STATUS bit1 now sets only after BOTH centroid and FWHM finish
 * (~1281 cycles after the line ends, due to the FWHM SCAN pass).
 * (matches Icarus sim and the Python golden model of the a4_pen_line image)
 */
#include <stdio.h>
#include "xparameters.h"
#include "xil_io.h"


/* From Vivado Address Editor — update if yours differ */
// #define SPR_BASE    0x43C00000UL      /* spr_accel_axi S_AXI on M_AXI_GP0 */
// #define GPIO_BASE   0x41200000UL      /* AXI GPIO, ch1 bit0 -> player trigger */

#define SPR_BASE    0x40000000UL   /* was 0x43C00000 placeholder */
#define GPIO_BASE   0x41200000UL   /* matches, no change */

#define SPR_CTRL     (SPR_BASE + 0x00)   /* [0] start_frame (self-clearing)  */
#define SPR_STATUS   (SPR_BASE + 0x04)   /* [0] busy, [1] done (W1C)         */
#define SPR_P_MIN    (SPR_BASE + 0x08)
#define SPR_DBG_NUM  (SPR_BASE + 0x0C)
#define SPR_DBG_DEN  (SPR_BASE + 0x10)
#define SPR_IRQ_CTRL (SPR_BASE + 0x14)   /* [0] irq_en, [1] W1C pending      */
#define SPR_FWHM     (SPR_BASE + 0x18)   /* [10:0] dip width at half-max     */
#define SPR_FWHM_CTR (SPR_BASE + 0x1C)   /* [10:0] dip pos from FWHM midpoint*/

#define GPIO_DATA    (GPIO_BASE + 0x00)
#define GPIO_TRI     (GPIO_BASE + 0x04)

int main(void)
{
    xil_printf("\r\n=== SPR accelerator bring-up ===\r\n");
    Xil_Out32(GPIO_TRI,  0x0);            /* GPIO ch1 as output */
    Xil_Out32(GPIO_DATA, 0x0);

    for (int frame = 1; frame <= 3; frame++) {
        Xil_Out32(SPR_STATUS, 0x2);       /* W1C stale done                    */
        Xil_Out32(SPR_CTRL,   0x1);       /* arm centroid FIRST (framing rule) */
        Xil_Out32(GPIO_DATA,  0x1);       /* then trigger the vector player    */

        u32 status, timeout = 1000000;
        do { status = Xil_In32(SPR_STATUS); }
        while (!(status & 0x2) && --timeout);
        Xil_Out32(GPIO_DATA, 0x0);

        if (!timeout) {
            xil_printf("frame %d: TIMEOUT status=0x%08x\r\n", frame, status);
            continue;
        }
        u32 pmin = Xil_In32(SPR_P_MIN);
        u32 num  = Xil_In32(SPR_DBG_NUM);
        u32 den  = Xil_In32(SPR_DBG_DEN);
        u32 fwhm = Xil_In32(SPR_FWHM);
        u32 fctr = Xil_In32(SPR_FWHM_CTR);
        xil_printf("frame %d: p_min=%u num=%u den=%u fwhm=%u fwhm_ctr=%u  %s\r\n",
                   frame, pmin, num, den, fwhm, fctr,
                   (pmin == 639 && den == 121834 && fwhm == 30 && fctr == 639)
                       ? "PASS" : "CHECK");
    }
    xil_printf("done.\r\n");
    return 0;
}
