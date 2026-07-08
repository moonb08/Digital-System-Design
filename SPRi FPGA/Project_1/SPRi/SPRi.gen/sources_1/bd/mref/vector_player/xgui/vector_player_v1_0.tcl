# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CUR_FILE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "GAP_CYCLES" -parent ${Page_0}
  ipgui::add_param $IPINST -name "IMAGE_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PIXEL_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "REF_FILE" -parent ${Page_0}


}

proc update_PARAM_VALUE.ADDR_WIDTH { PARAM_VALUE.ADDR_WIDTH } {
	# Procedure called to update ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ADDR_WIDTH { PARAM_VALUE.ADDR_WIDTH } {
	# Procedure called to validate ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.CUR_FILE { PARAM_VALUE.CUR_FILE } {
	# Procedure called to update CUR_FILE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CUR_FILE { PARAM_VALUE.CUR_FILE } {
	# Procedure called to validate CUR_FILE
	return true
}

proc update_PARAM_VALUE.GAP_CYCLES { PARAM_VALUE.GAP_CYCLES } {
	# Procedure called to update GAP_CYCLES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.GAP_CYCLES { PARAM_VALUE.GAP_CYCLES } {
	# Procedure called to validate GAP_CYCLES
	return true
}

proc update_PARAM_VALUE.IMAGE_WIDTH { PARAM_VALUE.IMAGE_WIDTH } {
	# Procedure called to update IMAGE_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.IMAGE_WIDTH { PARAM_VALUE.IMAGE_WIDTH } {
	# Procedure called to validate IMAGE_WIDTH
	return true
}

proc update_PARAM_VALUE.PIXEL_WIDTH { PARAM_VALUE.PIXEL_WIDTH } {
	# Procedure called to update PIXEL_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PIXEL_WIDTH { PARAM_VALUE.PIXEL_WIDTH } {
	# Procedure called to validate PIXEL_WIDTH
	return true
}

proc update_PARAM_VALUE.REF_FILE { PARAM_VALUE.REF_FILE } {
	# Procedure called to update REF_FILE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.REF_FILE { PARAM_VALUE.REF_FILE } {
	# Procedure called to validate REF_FILE
	return true
}


proc update_MODELPARAM_VALUE.PIXEL_WIDTH { MODELPARAM_VALUE.PIXEL_WIDTH PARAM_VALUE.PIXEL_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PIXEL_WIDTH}] ${MODELPARAM_VALUE.PIXEL_WIDTH}
}

proc update_MODELPARAM_VALUE.IMAGE_WIDTH { MODELPARAM_VALUE.IMAGE_WIDTH PARAM_VALUE.IMAGE_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.IMAGE_WIDTH}] ${MODELPARAM_VALUE.IMAGE_WIDTH}
}

proc update_MODELPARAM_VALUE.ADDR_WIDTH { MODELPARAM_VALUE.ADDR_WIDTH PARAM_VALUE.ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ADDR_WIDTH}] ${MODELPARAM_VALUE.ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.CUR_FILE { MODELPARAM_VALUE.CUR_FILE PARAM_VALUE.CUR_FILE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CUR_FILE}] ${MODELPARAM_VALUE.CUR_FILE}
}

proc update_MODELPARAM_VALUE.REF_FILE { MODELPARAM_VALUE.REF_FILE PARAM_VALUE.REF_FILE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.REF_FILE}] ${MODELPARAM_VALUE.REF_FILE}
}

proc update_MODELPARAM_VALUE.GAP_CYCLES { MODELPARAM_VALUE.GAP_CYCLES PARAM_VALUE.GAP_CYCLES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.GAP_CYCLES}] ${MODELPARAM_VALUE.GAP_CYCLES}
}

