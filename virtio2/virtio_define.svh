/******************************************************************************
 * 文件名称 : virtio_define.svh
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/06/23
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  06/23     Joe Jiang   初始化版本
 ******************************************************************************/
`timescale 1ns / 1ps

`ifndef _VIRTIO_DEFINES_
`define _VIRTIO_DEFINES_

`default_nettype none

`define DATA_WIDTH                      256
`define DATA_EMPTY                      $clog2(`DATA_WIDTH)

`define VIRTIO_Q_NUM                    256
`define VIRTIO_Q_WIDTH                  $clog2(`VIRTIO_Q_NUM)

`define DEV_NUM                         1024
`define DEV_ID_WIDTH                    $clog2(`DEV_NUM)

`define VIRTIO_RX_BUF_PKT_NUM           1024
`define VIRTIO_RX_BUF_PKT_NUM_WIDTH     $clog2(`VIRTIO_RX_BUF_PKT_NUM)

`define SLOT_NUM                        32
`define SLOT_WIDTH                      $clog2(`SLOT_NUM)

`define UID_NUM                         1024
`define UID_WIDTH                       $clog2(`UID_NUM)

`define IRQ_MERGE_UINT_NUM              8
`define IRQ_MERGE_UINT_NUM_WIDTH        $clog2(`IRQ_MERGE_UINT_NUM)

`define TIME_MAP_WIDTH                  2

typedef enum logic [1:0]  { 
    VIRTIO_NET_RX_TYPE = 2'b01,
    VIRTIO_NET_TX_TYPE = 2'b00,
    VIRTIO_BLK_TYPE    = 2'b10
}virtio_q_type_t;

typedef struct packed{
    virtio_q_type_t typ;
    logic [`VIRTIO_Q_WIDTH-1:0] qid;
} virtio_vq_t;

typedef enum logic [6:0]  { 
    VIRTIO_IDX_ENGINE_ERR_CODE_MASK = 7'b1110000
} virtio_idx_engine_err_code_mask;

typedef enum logic [6:0]  { 
    VIRTIO_ERR_CODE_NONE                                        = 7'h00,
    VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR                            = 7'h71,
    VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX                         = 7'h72,
    VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE                           = 7'h03,
    VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR                          = 7'h04,
    VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE                 = 7'h10,
    VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE            = 7'h11,
    VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE       = 7'h12,
    VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT                  = 7'h13,
    VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO                  = 7'h14,
    VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC                = 7'h15,
    VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO              = 7'h16,
    VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE               = 7'h17,
    VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN                      = 7'h18,
    VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR                           = 7'h19,
    VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE              = 7'h1a, //next over buf len
    VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE              = 7'h1b,
    VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR                           = 7'h20,
    VIRTIO_ERR_CODE_NETTX_PCIE_ERR                              = 7'h30,
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE             = 7'h40,
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE        = 7'h41,
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE   = 7'h42,
    VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT              = 7'h43,
    VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO              = 7'h44,
    VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC            = 7'h45,
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO             = 7'h46,
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_ONE             = 7'h47,
    VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR                       = 7'h48,
    VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE     = 7'h49,
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE          = 7'h4a,
    VIRTIO_ERR_CODE_BLK_DOWN_PCIE_ERR                           = 7'h50
}virtio_err_code_t;

typedef struct packed{
    logic fatal;
    virtio_err_code_t err_code;
}virtio_err_info_t;

typedef struct packed{
    virtio_vq_t vq;
    logic [15:0] id;//desc tbl指针
    //!err_pcie && !err_id_oversize && !local_ring_empty && q_stat_doing 有效
    logic local_ring_empty;
    logic avail_ring_empty;
    logic q_stat_doing;
    logic q_stat_stopping;
    logic [15:0] avail_idx; //id对应avail ring的位置，net场景用来写used
    virtio_err_info_t err_info;
}virtio_avail_id_rsp_dat_t;

typedef struct packed{
    virtio_vq_t vq;
    logic [ `VIRTIO_RX_BUF_PKT_NUM_WIDTH-1:0] pkt_id; //rx only
    logic ok;//ok = !local_ring_empty && q_stat_doing && err_info.err_code == VIRTIO_ERR_CODE_NONE && !desc_engine_limit;
    logic local_ring_empty;//没有id，硬件还没取到
    logic avail_ring_empty;//没有id，软件上被取完了
    logic q_stat_doing; //正在工作
    logic q_stat_stopping;//正在停止
    logic desc_engine_limit;
    virtio_err_info_t err_info;
} virtio_desc_eng_slot_rsp_t;

typedef struct packed{
    virtio_vq_t vq;
    logic [9:0] dev_id;
    logic[ `VIRTIO_RX_BUF_PKT_NUM_WIDTH-1:0] pkt_id;
    logic [17:0] total_buf_length;
    logic [15:0] valid_desc_cnt;
    logic [15:0] ring_id; //用于used_element.id
    logic [15:0] avail_idx; //用于used_idx
    logic forced_shutdown;
    virtio_err_info_t err_info;
} virtio_desc_eng_desc_rsp_sbd_t;

typedef struct packed{
    logic [12:0] rsv;
    logic indirect;
    logic write;
    logic next;
}virtq_desc_flags_t;

typedef struct packed{
    logic [15:0] next;
    virtq_desc_flags_t flags;
    logic [31:0]len;
    logic [63:0]addr;
}virtq_desc_t;

typedef struct packed{
    logic [31:0] len;
    logic [31:0] id;
}virtq_used_elem_t;

typedef struct packed{
    virtio_vq_t         vq;
    virtq_used_elem_t   elem;
    logic [15:0]        used_idx;
    logic               forced_shutdown;
    virtio_err_info_t   err_info;
} virtio_used_info_t;

typedef enum logic [3:0]  {
    VIRTIO_Q_STATUS_IDLE       = 4'b0001,
    VIRTIO_Q_STATUS_STARTING   = 4'b0010,
    VIRTIO_Q_STATUS_DOING      = 4'b0100,
    VIRTIO_Q_STATUS_STOPPING   = 4'b1000
}virtio_qstat_t;


`define VIRTIO_CTX_BDF                                           'h0
`define VIRTIO_CTX_DEV_ID                                        'h8
`define VIRTIO_CTX_AVAIL_RING_ADDR                              'h10
`define VIRTIO_CTX_USED_RING_ADDR                               'h18
`define VIRTIO_CTX_DESC_TBL_ADDR                                'h20
`define VIRTIO_CTX_QDEPTH                                       'h28
`define VIRTIO_CTX_INDIRCT_TSO_CSUM_EN                          'h30
`define VIRTIO_CTX_MAX_LEN                                      'h38
`define VIRTIO_CTX_GENERATION                                   'h40
`define VIRTIO_CTX_CTRL                                         'h48
`define VIRTIO_CTX_AVAIL_IDX_BLK_DS_PTR_BLK_US_PTR              'h50
`define VIRTIO_CTX_UI_PI_CI_USED_PTR                            'h58
`define VIRTIO_CTX_SOC_NOTIFY                                   'h60
`define VIRTIO_CTX_IDX_ENG_NO_NOTIFY_RD_REQ_RSP_NUM             'h68
`define VIRTIO_CTX_USED_ELEM_PTR_ERR_FATAL_FLAG                 'h70
`define VIRTIO_CTX_ERR_INFO                                     'h78
`define VIRTIO_CTX_MSIX_ADDR                                    'h80
`define VIRTIO_CTX_MSIX_DATA                                    'h88
`define VIRTIO_CTX_MSIX_ENABLE                                  'h90
`define VIRTIO_CTX_MSIX_MASK                                    'h98
`define VIRTIO_CTX_MSIX_PENDING                                 'ha0
`define VIRTIO_CTX_MSIX_AGGREGATION_TIME                        'ha8
`define VIRTIO_CTX_MSIX_AGGREGATION_THRESHOLD                   'hb0
`define VIRTIO_CTX_MSIX_AGGREGATION_INFO_LOW                    'hb8
`define VIRTIO_CTX_MSIX_AGGREGATION_INFO_HIGH                   'hc0
`define VIRTIO_CTX_QOS_ENABLE                                   'h100
`define VIRTIO_CTX_QOS_L1_UNIT                                  'h108
`define VIRTIO_CTX_NET_IDX_LIMIT_PER_QUEUE                      'h130
`define VIRTIO_CTX_BLK_DESC_ENG_DESC_TBL_ADDR                   'h150
`define VIRTIO_CTX_BLK_DESC_ENG_DESC_TBL_SIZE                   'h158
`define VIRTIO_CTX_BLK_DESC_ENG_DESC_TBL_NEXT_ID_CNT            'h160
`define VIRTIO_CTX_BLK_DESC_ENG_IS_INDIRCT_RESUMER_CHAIN_FST_SEG_DATA_LEN     'h168
`define VIRTIO_CTX_NET_DESC_ENG_HEAD_TAIL_SLOT                  'h180
`define VIRTIO_CTX_USED_IRQ_CNT                                 'h200
`define VIRTIO_CTX_NET_TX_IDX_LIMIT_PER_DEV                     'h8
`define VIRTIO_CTX_NET_RX_IDX_LIMIT_PER_DEV                     'h0

typedef struct packed {
    logic [15:0]                                             bdf;
    logic [`DEV_ID_WIDTH-1:0]                                dev_id;
    logic [63:0]                                             avail_ring_addr;
    logic [63:0]                                             used_ring_addr;
    logic [63:0]                                             desc_tbl_addr;
    logic [3:0]                                              qdepth;
    logic [19:0]                                             max_len;
    logic [7:0]                                              generation;
    logic                                                    forced_shutdown;
    virtio_qstat_t                                           q_status;
    logic [15:0]                                             blk_ds_ptr;
    logic [15:0]                                             blk_us_ptr;
    logic [15:0]                                             avail_idx;
    logic [15:0]                                             used_ptr;
    logic [15:0]                                             ci_ptr;
    logic [15:0]                                             pi_ptr;
    logic [15:0]                                             ui_ptr;
    logic                                                    no_notify_flag;
    logic                                                    no_change_flag;
    logic [6:0]                                              idx_engine_rd_rsp_num;
    logic [6:0]                                              idx_engine_rd_req_num;
    logic                                                    used_err_fatal_flag;
    logic [16:0]                                             used_elem_ptr;
    virtio_err_info_t                                        err_info;
    logic [63:0]                                             msix_addr;
    logic [31:0]                                             msix_data;
    logic                                                    msix_enable;
    logic                                                    msix_mask;
    logic                                                    msix_pending;
    logic [`IRQ_MERGE_UINT_NUM*3-1:0]                        msix_aggregation_time;
    logic [6:0]                                              msix_aggregation_threshold;
    logic [(`IRQ_MERGE_UINT_NUM*(`TIME_MAP_WIDTH+8))/2-1:0]  msix_aggregation_info_low;
    logic [(`IRQ_MERGE_UINT_NUM*(`TIME_MAP_WIDTH+8))/2-1:0]  msix_aggregation_info_high;
    logic                                                    qos_enable;
    logic [15:0]                                             qos_l1_unit;
    logic [7:0]                                              net_idx_limit_per_queue;
    logic [7:0]                                              net_tx_idx_limit_per_dev;
    logic [7:0]                                              net_rx_idx_limit_per_dev;
    logic [63:0]                                             blk_desc_eng_desc_tbl_addr;
    logic [31:0]                                             blk_desc_eng_desc_tbl_size;
    logic [63:0]                                             blk_desc_eng_desc_next_id_desc_cnt;
    logic [63:0]                                             blk_desc_eng_is_indirct_resumer_data_len;
    logic [(`SLOT_WIDTH*2+1)-1:0]                            net_desc_eng_tail_vld_head_slot;
    logic [2:0]                                              indirct_support_tso_en_csum_en;
    logic                                                    used_dma_write_used_idx_irq_flag;
    logic [15:0]                                             virtio_used_send_irq_cnt;
}virtio_ctx_info_t;

`default_nettype wire

`endif
