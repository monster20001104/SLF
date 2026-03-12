'''
Author: Joe Jiang
Date: 2024-06-01 19:39:55
LastEditTime: 2024-07-19 11:32:37
LastEditors: Joe Jiang
Description: 
FilePath: /PeakRDL-verilog/example.py
Copyright (c) 2024 Yucca
'''
import sys
from systemrdl import RDLCompiler, RDLCompileError
from peakrdl.verilog import VerilogExporter

rdlc = RDLCompiler()

if len(sys.argv) == 2:
    name = sys.argv[1]
else:
    name = "example"
try:
    rdlc.compile_file("./{}.rdl".format(name))
    root = rdlc.elaborate()
except RDLCompileError:
    sys.exit(1)

exporter = VerilogExporter()
exporter.export(root, "./{}".format(name))
