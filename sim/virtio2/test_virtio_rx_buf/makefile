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
COV ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

DUT      = virtio_rx_buf_tb
TOPLEVEL = $(DUT)
MODULE   = test_$(DUT)
cur_dir	 = $(shell pwd)

# 使用Makefile条件判断检查并创建cov_scope.txt，写入默认模块列表
ifeq ($(wildcard cov_scope.txt),)

  $(shell echo "+tree $(TOPLEVEL) 0" > cov_scope.txt)
  $(shell echo "-module yucca_sync_fifo" >> cov_scope.txt)
  $(shell echo "-module scfifo" >> cov_scope.txt)
  $(shell echo "-module sync_simple_dual_port_ram" >> cov_scope.txt)
  $(shell echo "-module altera_syncram" >> cov_scope.txt)
  $(shell echo "-module sync_true_dual_port_ram" >> cov_scope.txt)
  $(shell echo "-module rr_sch" >> cov_scope.txt)
  $(shell echo "-module dwrr_sch" >> cov_scope.txt)
  $(shell echo "-module pkt_fifo" >> cov_scope.txt)
  $(shell echo "-module ALTERA_DEVICE_FAMILIES" >> cov_scope.txt)
  $(shell echo "-module ALTERA_LNSIM_MEMORY_INITIALIZATION" >> cov_scope.txt)
  $(shell echo "-module mlite_if" >> cov_scope.txt)
  $(info Created default cov_scope.txt)
else
endif

COMPILE_ARGS += -F $(cur_dir)/filelist.txt +define+VIRTIO_RX_BUF_PKT_NUM=1024
COMPILE_ARGS += -full64 -cpp g++ -cc gcc -LDFLAGS -no-pie -LDFLAGS -Wl,--no-as-needed -CFLAGS -fPIE -kdb -xinit=0  -debug_access
COMPILE_ARGS += -cm line+cond+fsm+tgl+branch+assert -cm_nocasedef -cm_hier $(shell pwd)/cov_scope.txt
SIM_ARGS 	 += -cm line+cond+fsm+tgl+branch+assert -cm_nocasedef


# 覆盖率结果目录和合并报告目录
COV_DIR = $(cur_dir)/cov_result
MERGED_COV_DIR = $(COV_DIR)/merged
MERGE_LOG = $(MERGED_COV_DIR)/merge.log

RUN_ID := $(shell DATE=$$(date +%Y%m%d%H%M%S); RND=$$((RANDOM%100)); echo "run_$${DATE}_$$(printf "%02d" $$RND)")

ifeq ($(COV), 1)
$(shell mkdir -p $(COV_DIR))
COMPILE_ARGS += -cm_dir $(COV_DIR)/$(RUN_ID)
endif

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

report:
ifndef FSDB
	$(error 请使用 FSDB=filename.fsdb 指定要查看的FSDB文件)
else
	verdi -dbdir sim_build/simv.daidir/  -managercFile ~/manage.rc  -ssf $(FSDB)
endif

clean::
	@rm -rf iverilog_dump.v
	@rm -rf *.fst *.fsdb
	@rm -rf __pycache__ *.log *.xml
	@rm -rf *.rc *.conf verdiLog *.vf
	@rm -rf .tmp*
	@rm -rf vdCovLog

# URG覆盖率合并目标
cov_merge:
	@mkdir -p $(MERGED_COV_DIR); \
	urg -full64 -format both -noreport \
		-dir $(COV_DIR)/*.vdb \
		-dbname $(MERGED_COV_DIR)/simv_merge.vdb; \
	echo "Coverage merged into $(MERGED_COV_DIR)/simv_merge.vdb" ;

# 使用Verdi查看覆盖率
cov_report:
	@if [ -d "$(MERGED_COV_DIR)/simv_merge.vdb" ]; then \
		echo "Opening merged coverage in Verdi..."; \
		verdi -cov -covdir $(MERGED_COV_DIR)/simv_merge.vdb & \
	elif [ "$$(ls -A $(COV_DIR)/*.vdb 2>/dev/null)" ]; then \
		echo "Opening latest coverage in Verdi..."; \
		verdi -cov -covdir $(shell ls -td $(COV_DIR)/*.vdb | head -1) & \
	else \
		echo "Error: No coverage database found. Please run simulations first."; \
		exit 1; \
	fi

# 清理覆盖率相关文件
cov_clean:
	@rm -rf $(COV_DIR);

clean_all: clean cov_clean
	@echo "All clean operations completed"