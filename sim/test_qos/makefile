# Copyright (c) 2020 Alex Forencich
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

TOPLEVEL_LANG = verilog

SIM ?= vcs
WAVES ?= 1

CLK_FREQ ?= 220M
COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

DUT      = qos_tb
TOPLEVEL = qos_tb
MODULE   = test_$(DUT)
cur_dir	 = $(shell pwd)

COMPILE_ARGS += -F $(cur_dir)/filelist.txt
COMPILE_ARGS += +define+MS_100_CLEAN_CNT_AT_USER_CLK=32\'d22000000
COMPILE_ARGS += -full64 -cpp g++ -cc gcc -LDFLAGS -no-pie -LDFLAGS -Wl,--no-as-needed -CFLAGS -fPIE -kdb -xinit=0  -debug_access
COMPILE_ARGS += -cm line+cond+fsm+tgl+branch+assert -cm_nocasedef -cm_hier $(shell pwd)/cov_scope.txt
SIM_ARGS 	 += -cm line+cond+fsm+tgl+branch+assert -cm_nocasedef

LEN_PKT_MODES ?= len_mode,pkt_mode,len_pkt_mode
SEC_EN_MODES ?= sec_en_11,sec_en_01
UID_CNT_MODES ?= uid_cnt_100, uid_cnt_111

run:
	export COCOTB_LEN_PKT_MODES=$(LEN_PKT_MODES); \
	export COCOTB_SEC_EN_MODES=$(SEC_EN_MODES); \
	export COCOTB_UID_CNT_MODES=$(UID_CNT_MODES); \
	export COCOTB_CLK_FREQ=$(CLK_FREQ); \
	export WAVE_FILE=$(WAVE_FILE); \
	$(MAKE) sim 

clk_200m:
	$(MAKE) run CLK_FREQ=200M

clk_220m:
	$(MAKE) run CLK_FREQ=220M

len_pkt_1:
	$(MAKE) run LEN_PKT_MODES=len_mode

len_pkt_2:
	$(MAKE) run LEN_PKT_MODES=pkt_mode

len_pkt_3:
	$(MAKE) run LEN_PKT_MODES=len_pkt_mode

sec_en1:
	$(MAKE) run SEC_EN_MODES=sec_en_11

sec_en2:
	$(MAKE) run SEC_EN_MODES=sec_en_01

uid_cnt1:
	$(MAKE) run UID_CNT_MODES=uid_cnt_100

uid_cnt2:
	$(MAKE) run UID_CNT_MODES=uid_cnt_111

all: 
	$(MAKE) run
	@echo "All cases completed!"

ifeq ($(SIM), icarus)
	PLUSARGS += -fst

	COMPILE_ARGS += -P $(TOPLEVEL).ADDR_OFFSET=$(ADDR_OFFSET)
	COMPILE_ARGS += -P $(TOPLEVEL).ADDR_WIDTH=$(ADDR_WIDTH)
	COMPILE_ARGS += -P $(TOPLEVEL).DATA_WIDTH=$(DATA_WIDTH)

	ifeq ($(WAVES), 1)
		VERILOG_SOURCES += iverilog_dump.v
		COMPILE_ARGS += -s iverilog_dump
		iverilog_dump.v:
			echo 'module iverilog_dump();' > $@
			echo 'initial begin' >> $@
			echo '    $$dumpfile("$(WAVE_FILE)");' >> $@
			echo '    $$dumpvars(0, $(TOPLEVEL));' >> $@
			echo 'end' >> $@
			echo 'endmodule' >> $@
	endif
else ifeq ($(SIM), verilator)
	COMPILE_ARGS += -Wno-SELRANGE -Wno-WIDTH

	COMPILE_ARGS += -GADDR_OFFSET=$(ADDR_OFFSET)
	COMPILE_ARGS += -GADDR_WIDTH=$(ADDR_WIDTH)
	COMPILE_ARGS += -GDATA_WIDTH=$(DATA_WIDTH)

	ifeq ($(WAVES), 1)
		COMPILE_ARGS += --trace-fst --trace-file $(WAVE_FILE)
	endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

iverilog_dump.v:
	echo 'module iverilog_dump();' > $@
	echo 'initial begin' >> $@
	echo '    $$dumpfile("$(TOPLEVEL).fst");' >> $@
	echo '    $$dumpvars(0, $(TOPLEVEL));' >> $@
	echo 'end' >> $@
	echo 'endmodule' >> $@

clean::
	@rm -rf iverilog_dump.v
	@rm -rf *.fst *.fsdb
	@rm -rf __pycache__ *.log *.xml
	@rm -rf *.rc *.conf verdiLog *.vf vdCovLog
