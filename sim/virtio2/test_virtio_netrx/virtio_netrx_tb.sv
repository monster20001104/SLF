/******************************************************************************
 * 文件名称 : virtio_netrx_tb.sv
 * 作者名称 : Liuch
 * 创建日期 : 2026/01/21
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0   26/01/21      Liuch       初始化版本
 ******************************************************************************/
`include "virtio_netrx_define.svh"
`include "tlp_adap_dma_if.svh"
module virtio_netrx_tb
    import alt_tlp_adaptor_pkg::*;
#(
    parameter DATA_WIDTH = 256,
    parameter DATA_EMPTY = $clog2(DATA_WIDTH / 8),
    parameter VIRTIO_Q_NUM = 256,
    parameter VIRTIO_Q_WIDTH = $clog2(VIRTIO_Q_NUM)

) (
    input  logic                                              clk,
    input  logic                                              rst,
    //
    input  logic                                              netrx_info_vld,
    input  logic [       $bits(virtio_rx_buf_req_info_t)-1:0] netrx_info_data,
    output logic                                              netrx_info_rdy,
    //
    output logic                                              netrx_alloc_slot_req_vld,
    output logic [                    $bits(virtio_vq_t)-1:0] netrx_alloc_slot_req_data,
    output logic [                                      15:0] netrx_alloc_slot_req_dev_id,
    output logic [                                       9:0] netrx_alloc_slot_req_pkt_id,
    input  logic                                              netrx_alloc_slot_req_rdy,
    //
    input  logic                                              netrx_alloc_slot_rsp_vld,
    input  logic [     $bits(virtio_desc_eng_slot_rsp_t)-1:0] netrx_alloc_slot_rsp_data,
    output logic                                              netrx_alloc_slot_rsp_rdy,
    //
    output logic                                              slot_ctrl_dev_id_rd_req_vld,
    output logic [                    $bits(virtio_vq_t)-1:0] slot_ctrl_dev_id_rd_req_qid,
    //
    input  logic                                              slot_ctrl_dev_id_rd_rsp_vld,
    input  logic [                                      15:0] slot_ctrl_dev_id_rd_rsp_data,
    //
    output logic                                              netrx_desc_rsp_rdy,
    input  logic                                              netrx_desc_rsp_vld,
    input  logic                                              netrx_desc_rsp_sop,
    input  logic                                              netrx_desc_rsp_eop,
    input  logic [ $bits(virtio_desc_eng_desc_rsp_sbd_t)-1:0] netrx_desc_rsp_sbd,
    input  logic [                   $bits(virtq_desc_t)-1:0] netrx_desc_rsp_data,
    //
    output logic                                              rd_data_req_vld,
    output logic [    $bits(virtio_rx_buf_rd_data_req_t)-1:0] rd_data_req_data,
    input  logic                                              rd_data_req_rdy,
    //
    input  logic                                              rd_data_rsp_vld,
    input  logic                                              rd_data_rsp_sop,
    input  logic                                              rd_data_rsp_eop,
    input  logic [                            DATA_EMPTY-1:0] rd_data_rsp_sty,
    input  logic [                            DATA_EMPTY-1:0] rd_data_rsp_mty,
    input  logic [                            DATA_WIDTH-1:0] rd_data_rsp_data,
    output logic                                              rd_data_rsp_rdy,
    input  logic [$bits(virtio_rx_buf_rd_data_rsp_sbd_t)-1:0] rd_data_rsp_sbd,
    //
    input  logic                                              dma_wr_req_sav,
    output logic                                              dma_wr_req_val,
    output logic                                              dma_wr_req_sop,
    output logic                                              dma_wr_req_eop,
    output logic [                            DATA_WIDTH-1:0] dma_wr_req_data,
    output logic [                            DATA_EMPTY-1:0] dma_wr_req_sty,
    output logic [                            DATA_EMPTY-1:0] dma_wr_req_mty,
    output logic [                         $bits(desc_t)-1:0] dma_wr_req_desc,
    //
    output logic                                              wr_data_ctx_rd_req_vld,
    output logic [                    $bits(virtio_vq_t)-1:0] wr_data_ctx_rd_req_qid,
    //
    input  logic                                              wr_data_ctx_rd_rsp_vld,
    input  logic [                                      15:0] wr_data_ctx_rd_rsp_bdf,
    input  logic                                              wr_data_ctx_rd_rsp_forced_shutdown,
    //
    input  logic                                              dma_wr_rsp_val,
    input  logic [                                      63:0] dma_wr_rsp_rd2rsp_loop,
    //
    output logic                                              used_info_vld,
    output logic [             $bits(virtio_used_info_t)-1:0] used_info_data,
    input  logic                                              used_info_rdy


);

    logic [63:0] dma_wr_req_addr;
    logic [31:0] dma_wr_req_len;
    logic [63:0] dma_wr_req_sbd;
    logic [15:0] dma_wr_req_bdf, dma_wr_req_dev_id;

    tlp_adap_dma_wr_req_if #(.DATA_WIDTH(DATA_WIDTH)) dma_wr_req ();
    tlp_adap_dma_wr_rsp_if #(.DATA_WIDTH(DATA_WIDTH)) dma_wr_rsp ();


    assign dma_wr_req.sav         = dma_wr_req_sav;
    assign dma_wr_req_val         = dma_wr_req.vld;
    assign dma_wr_req_sop         = dma_wr_req.sop;
    assign dma_wr_req_eop         = dma_wr_req.eop;
    assign dma_wr_req_data        = dma_wr_req.data;
    assign dma_wr_req_sty         = dma_wr_req.sty;
    assign dma_wr_req_mty         = dma_wr_req.mty;
    assign dma_wr_req_desc        = dma_wr_req.desc;

    assign dma_wr_rsp.vld         = dma_wr_rsp_val;
    assign dma_wr_rsp.rd2rsp_loop = dma_wr_rsp_rd2rsp_loop;


    mlite_if #(
        .ADDR_WIDTH (64),
        .DATA_WIDTH (64),
        .CHANNEL_NUM(1)
    ) mlite_master ();

    virtio_netrx_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_EMPTY(DATA_EMPTY),
        .VIRTIO_Q_NUM(VIRTIO_Q_NUM),
        .VIRTIO_Q_WIDTH(VIRTIO_Q_WIDTH)

    ) u_virtio_netrx_top (

        .clk                               (clk),
        .rst                               (rst),
        //
        .netrx_info_vld                    (netrx_info_vld),
        .netrx_info_data                   (netrx_info_data),
        .netrx_info_rdy                    (netrx_info_rdy),
        //
        .dma_wr_req                        (dma_wr_req),
        .dma_wr_rsp                        (dma_wr_rsp),
        //
        .netrx_alloc_slot_req_vld          (netrx_alloc_slot_req_vld),
        .netrx_alloc_slot_req_data         (netrx_alloc_slot_req_data),
        .netrx_alloc_slot_req_dev_id       (netrx_alloc_slot_req_dev_id),
        .netrx_alloc_slot_req_pkt_id       (netrx_alloc_slot_req_pkt_id),
        .netrx_alloc_slot_req_rdy          (netrx_alloc_slot_req_rdy),
        //
        .netrx_alloc_slot_rsp_vld          (netrx_alloc_slot_rsp_vld),
        .netrx_alloc_slot_rsp_data         (netrx_alloc_slot_rsp_data),
        .netrx_alloc_slot_rsp_rdy          (netrx_alloc_slot_rsp_rdy),
        //
        .slot_ctrl_dev_id_rd_req_vld       (slot_ctrl_dev_id_rd_req_vld),
        .slot_ctrl_dev_id_rd_req_qid       (slot_ctrl_dev_id_rd_req_qid),
        //
        .slot_ctrl_dev_id_rd_rsp_vld       (slot_ctrl_dev_id_rd_rsp_vld),
        .slot_ctrl_dev_id_rd_rsp_data      (slot_ctrl_dev_id_rd_rsp_data),
        //
        .netrx_desc_rsp_rdy                (netrx_desc_rsp_rdy),
        .netrx_desc_rsp_vld                (netrx_desc_rsp_vld),
        .netrx_desc_rsp_sop                (netrx_desc_rsp_sop),
        .netrx_desc_rsp_eop                (netrx_desc_rsp_eop),
        .netrx_desc_rsp_sbd                (netrx_desc_rsp_sbd),
        .netrx_desc_rsp_data               (netrx_desc_rsp_data),
        //
        .rd_data_req_vld                   (rd_data_req_vld),
        .rd_data_req_data                  (rd_data_req_data),
        .rd_data_req_rdy                   (rd_data_req_rdy),
        //
        .rd_data_rsp_vld                   (rd_data_rsp_vld),
        .rd_data_rsp_sop                   (rd_data_rsp_sop),
        .rd_data_rsp_eop                   (rd_data_rsp_eop),
        .rd_data_rsp_sty                   (rd_data_rsp_sty),
        .rd_data_rsp_mty                   (rd_data_rsp_mty),
        .rd_data_rsp_data                  (rd_data_rsp_data),
        .rd_data_rsp_rdy                   (rd_data_rsp_rdy),
        .rd_data_rsp_sbd                   (rd_data_rsp_sbd),
        //
        .wr_data_ctx_rd_req_vld            (wr_data_ctx_rd_req_vld),
        .wr_data_ctx_rd_req_qid            (wr_data_ctx_rd_req_qid),
        //
        .wr_data_ctx_rd_rsp_vld            (wr_data_ctx_rd_rsp_vld),
        .wr_data_ctx_rd_rsp_bdf            (wr_data_ctx_rd_rsp_bdf),
        .wr_data_ctx_rd_rsp_forced_shutdown(wr_data_ctx_rd_rsp_forced_shutdown),
        //
        .used_info_vld                     (used_info_vld),
        .used_info_data                    (used_info_data),
        .used_info_rdy                     (used_info_rdy),
        //
        .dfx_slave                         (mlite_master)
    );


    initial begin
        $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
        $fsdbDumpvars(0, virtio_netrx_tb, "+all");
        $fsdbDumpMDA();
    end
    
endmodule
