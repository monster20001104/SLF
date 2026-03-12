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

DUT      = dwrr_sch_tb
TOPLEVEL = dwrr_sch_tb
MODULE   = test_$(DUT)
cur_dir	 = $(shell pwd)

# module parameters
export SH_NUM ?= 4

COMPILE_ARGS += -F $(cur_dir)/filelist.txt
COMPILE_ARGS += -pvalue+SH_NUM=$(SH_NUM)
COMPILE_ARGS += -full64 -cpp g++ -cc gcc -LDFLAGS -no-pie -LDFLAGS -Wl,--no-as-needed -CFLAGS -fPIE -kdb -xinit=0  -debug_access -debug_pp

ifeq ($(SIM), icarus)
	PLUSARGS += -fst

	COMPILE_ARGS += -P $(TOPLEVEL).ADDR_OFFSET=$(ADDR_OFFSET)
	COMPILE_ARGS += -P $(TOPLEVEL).ADDR_WIDTH=$(ADDR_WIDTH)
	COMPILE_ARGS += -P $(TOPLEVEL).DATA_WIDTH=$(DATA_WIDTH)

	ifeq ($(WAVES), 1)
		VERILOG_SOURCES += iverilog_dump.v
		COMPILE_ARGS += -s iverilog_dump
	endif
else ifeq ($(SIM), verilator)
	COMPILE_ARGS += -Wno-SELRANGE -Wno-WIDTH

	COMPILE_ARGS += -GADDR_OFFSET=$(ADDR_OFFSET)
	COMPILE_ARGS += -GADDR_WIDTH=$(ADDR_WIDTH)
	COMPILE_ARGS += -GDATA_WIDTH=$(DATA_WIDTH)

	ifeq ($(WAVES), 1)
		COMPILE_ARGS += --trace-fst
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
	@rm -rf dump.fst *.fsdb
	@rm -rf results.xml __pycache__ *.log top.*
