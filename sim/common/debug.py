#!/usr/bin/env python3
################################################################################
#  文件名称 : debug.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/12/25
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  12/25     Joe Jiang   初始化版本
################################################################################
import os
import signal
from remote_pdb import RemotePdb
import warnings
warnings.simplefilter("ignore", ResourceWarning)
debugger = RemotePdb("127.0.0.1", 4444)
print("press kill -10 {} to halt".format(os.getpid()))
print("press c to continue")

debugger.set_trace()
def handle_pdb(sig, frame):
    debugger.set_trace()
signal.signal(signal.SIGUSR1, handle_pdb)