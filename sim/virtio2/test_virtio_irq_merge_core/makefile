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

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps
LOG_FILE ?= compile.log

DUT      = virtio_irq_merge_core_tb
TOPLEVEL = $(DUT)
MODULE   = test_$(DUT)
cur_dir	 = $(shell pwd)

COMPILE_ARGS += -F $(cur_dir)/filelist.txt
COMPILE_ARGS += -full64 -cpp g++ -cc gcc -LDFLAGS -no-pie -LDFLAGS -Wl,--no-as-needed -CFLAGS -fPIE -kdb -xinit=0  -debug_access
COMPILE_ARGS += -cm line+cond+fsm+tgl+branch+assert -cm_nocasedef -cm_hier $(shell pwd)/cov_scope.txt
SIM_ARGS 	 += -cm line+cond+fsm+tgl+branch+assert -cm_nocasedef
ifeq ($(SIM), vcs)
    COMPILE_ARGS += -l $(LOG_FILE)
endif
THRESHOLD_MODES ?= threshold_0,threshold_1,threshold_2_127,threshold_mixed
QID_MODES ?= 8_channel,single_channel,4_channel,single_qid

run:
	export COCOTB_THRESHOLD_MODES=$(THRESHOLD_MODES); \
	export COCOTB_QID_MODES=$(QID_MODES); \
	export WAVE_FILE=$(WAVE_FILE); \
	$(MAKE) sim 

threshold_0:
	$(MAKE) run THRESHOLD_MODES=threshold_0 QID_MODES=8_channel

threshold_1:
	$(MAKE) run THRESHOLD_MODES=threshold_1 QID_MODES=8_channel

threshold_2_127:
	$(MAKE) run THRESHOLD_MODES=threshold_2_127 QID_MODES=8_channel

threshold_mixed:
	$(MAKE) run THRESHOLD_MODES=threshold_mixed QID_MODES=8_channel

qid_8channel:
	$(MAKE) run QID_MODES=8_channel

qid_single:
	$(MAKE) run QID_MODES=single_channel

qid_4channel:
	$(MAKE) run QID_MODES=4_channel

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

wave:
	@if [ $(words $(MAKECMDGOALS)) -le 1 ]; then \
		echo "错误：请指定波形文件后缀 用法:make wave 000"; \
		exit 1; \
	fi
	$(eval NUM := $(word 2, $(MAKECMDGOALS)))
	verdi -dbdir sim_build/simv.daidir/  -managercFile ~/.manage.rc  -ssf top_$(NUM).fsdb


clean::
	@rm -rf iverilog_dump.v
	@rm -rf *.fst *.fsdb
	@rm -rf __pycache__ *.log *.xml
	@rm -rf *.rc *.conf verdiLog *.vf vdCovLog