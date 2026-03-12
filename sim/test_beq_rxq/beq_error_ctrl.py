from enum import Enum, auto
import random

class DropErrorType(Enum):
    RD_NDESC_OVERFLOW = auto()  # rd_ndesc > 24
    DROP_MODE = auto()  # drop_mode=1
    QUEUE_DISABLED = auto()     # q_disable=1

class DescErrorType(Enum):
    INVALID_ADDR = auto()  # addr=0
    INVALID_LEN  = auto()  # len=0
    CORRUPT_FLAG = auto() # phase_tag != avail
   

class beq_error_ctrl:
    def __init__(self):
        self.is_fit_prob = 0      # 10%
        self.desc_err_ratio = 0   # is_fit:50% desc err
        self.drop_err_ratio = 0   # is_fit:50% drop_err

        #mixed test
        self.mixed_mode = True
        self.mixed_phase = 1

    def should_enter_fit_mode(self):
        return random.random() < self.is_fit_prob

    def select_error_type(self):
        #is_fit = 1
        return 'desc_err' if random.random() < self.desc_err_ratio else 'drop_err'

    def select_drop_subtype(self):
        #select drop type 1/3
        #return random.choice(list(DropErrorType))
        #return DropErrorType.RD_NDESC_OVERFLOW
        if self.mixed_mode:
            if self.mixed_phase == 1:
                return DropErrorType.QUEUE_DISABLED
            else:
                return DropErrorType.RD_NDESC_OVERFLOW
        else:
            return random.choice(list(DropErrorType))


    
    def select_desc_subtype(self):
        return random.choice(list(DescErrorType))
