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
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
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

DUT      ?= virtio_blk_tb
TOPLEVEL = $(DUT)
MODULE   = test_$(DUT)
cur_dir	 = $(shell pwd)

COMPILE_ARGS += -F $(cur_dir)/filelist.txt
COMPILE_ARGS += -full64 -cpp g++ -cc gcc -LDFLAGS -no-pie -LDFLAGS -Wl,--no-as-needed -CFLAGS -fPIE -kdb -O3 +no_notifier  -debug_access -debug_pp
#if needed, enable coverage with the following options
#COMPILE_ARGS += -cm line+cond+fsm+tgl+branch+assert -cm_nocasedef -cm_hier $(shell pwd)/cov_scope.txt -cm_fsmopt report2StateFsms
#SIM_ARGS    += -cm line+cond+fsm+tgl+branch+assert -cm_nocasedef

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
	@rm -rf dump.fst top.fsdb
	@rm -rf results.xml
	@rm -rf top_*.fsdb

report:
ifndef FSDB
	$(error 请使用 FSDB=filename.fsdb 指定要查看的FSDB文件)
else
	verdi -dbdir sim_build/simv.daidir/  -managercFile ~/manage.rc  -ssf $(FSDB)
endif
