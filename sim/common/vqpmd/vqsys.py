import os

test_qtype = os.getenv('TEST_QTYPE')

if test_qtype == 'blk':
    from vqpmd.vqblk import *
else:
    from vqpmd.vqnet import *
