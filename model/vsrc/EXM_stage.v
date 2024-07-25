`include "define.vh"

module EXM_stage(
    input clk,
    input reset,
    //for ID
    output es_ready,
    input ds_to_es_valid,
    input [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus,
    //for WB
    input ws_ready,
    output [1:0] es_to_ws_valid,
    output [`ES_TO_WS_BUS_WD -1:0] es_to_ws_bus,
    output nblock,

    input [`FORWAED_BUS_WD -1:0] forward_data1,
    input [`FORWAED_BUS_WD -1:0] forward_data2,
    output [`FORWAED_BUS_WD -1:0] exm_forward_bus,

    output [`BR_BUS_WD -1:0] br_bus,
    output        flush_IF,
    output        flush_ID,

    input [`EXM_DCACHE_RD -1:0] dcache_rdata_bus,
    output [`EXM_DCACHE_WD -1:0] dcache_wdata_bus
);
//reg  [`FORWAED_BUS_WD -1:0]  exm_forward_bus_r;
//wire [`FORWAED_BUS_WD -1:0]  exm_forward_bus_w;

wire [                 11:0] alu_op;
wire [                  3:0] bit_width;
wire                         may_jump;  // 1 
wire                         use_rj_value;  // 1
wire                         use_less;  // 1
wire                         need_less;  // 1
wire                         use_zero;  // 1
wire                         need_zero;  // 1
wire                         src1_is_pc;
wire                         src2_is_imm;
wire                         src2_is_4;
wire                         gr_we;
wire                         mem_we;
wire [                  4:0] dest;
wire [                 31:0] imm;
wire [                  4:0] rf_raddr1;
wire [                  4:0] rf_raddr2;
wire [                 31:0] rj_value;
wire [                 31:0] rj_value_t;
wire [                 31:0] rkd_value;
wire [                 31:0] rkd_value_t;
wire [                 31:0] es_pc;
wire                         is_jump;
wire                         res_from_mem;
wire                         use_mul;
wire                         use_high;
wire                         is_unsigned;
wire                         use_div;
wire                         use_mod;

wire                         pre_fail;

wire [                 31:0] src1;
wire [                 31:0] src2;
wire [                 31:0] alu_result; 
wire [                 31:0] mul_result;
wire [                 31:0] div_result;
wire [                 31:0] mem_result;
wire [                 31:0] final_result;

wire                  [31:0] jump_target;
wire                         zero;
wire                         less;

//wire                         dcache_ok;
wire [                 1:0]  es_to_ws_valid_w;
wire [`ES_TO_WS_BUS_WD-1:0]  es_to_ws_bus_w;
reg  [`ES_TO_WS_BUS_WD+1:0]  es_to_ws_bus_r;
wire                         dcache_ok;

assign {
    alu_op,  // 12  操作类型
    bit_width,  // 4  访存宽度 ls
    may_jump,  // 1   跳转 分支处理 ---
    use_rj_value,  // 1  绝对跳转
    use_less,  // 1    跳转需要   0无意义
    need_less,  // 1   1 1 1跳   1 0 0跳
    use_zero,  // 1
    need_zero,  // 1
    src1_is_pc,  // 1   操作数1为pc
    src2_is_imm,  // 1  操作数2为立即数
    src2_is_4,  // 1    操作数2为pc+
    gr_we,  // 1    写寄存器
    mem_we,  // 1   写内存 store
    dest,  // 5   目的地址
    imm,  // 32  立即数
    rf_raddr1,  //5    操作数1寄存器rj地址
    rf_raddr2,  //5    操作数2寄存器rk\rd地址
    rj_value_t,  // 32   操作数1（绝对跳转的地址
    rkd_value_t,  // 32  操作数2
    es_pc,  // 32   这条指令pc
    is_jump,  //1
    res_from_mem,  //1  读内存 load
    use_mul,
    use_high,
    is_unsigned,
    use_div,
    use_mod
} = ds_to_es_bus;

//assign es_ready_go = 1'b1;
assign nblock = dcache_ok || ~ds_to_es_valid;
assign es_to_ws_valid_w[0] = ds_to_es_valid;
assign es_to_ws_valid_w[1] = nblock;
assign es_to_ws_bus_w = {gr_we, dest, final_result, es_pc};
//assign exm_forward_bus_w = {final_result, dest, gr_we};

assign es_ready = nblock & ws_ready; 

always @(posedge clk) begin
    if (reset) begin
      es_to_ws_bus_r <= 0;
      es_to_ws_bus_r[`ES_TO_WS_BUS_WD+1]<=1'b1;
      //exm_forward_bus_r <= 0;
    //end //else if (!ws_ready) begin
    //   es_to_ws_bus_r <= es_to_ws_bus_r;
    //   //exm_forward_bus_r <= exm_forward_bus_r;
    end else begin
      es_to_ws_bus_r[`ES_TO_WS_BUS_WD-1:0] <= es_to_ws_bus_w;
      es_to_ws_bus_r[`ES_TO_WS_BUS_WD+1:`ES_TO_WS_BUS_WD] <= es_to_ws_valid_w;
     //exm_forward_bus_r <= exm_forward_bus_w;
    end
end


assign es_to_ws_valid  = es_to_ws_bus_r[`ES_TO_WS_BUS_WD+1:`ES_TO_WS_BUS_WD];
assign es_to_ws_bus    = es_to_ws_bus_r[`ES_TO_WS_BUS_WD-1:0];
assign exm_forward_bus = es_to_ws_bus_r[`ES_TO_WS_BUS_WD:32]; //exm_forward_bus_r;

assign rj_value =  (forward_data1[38] && forward_data1[37] && forward_data1[36:32]==rf_raddr1) ? forward_data1[31:0] : (forward_data2[38] && forward_data2[37] && forward_data2[36:32]==rf_raddr1) ? forward_data2[31:0] :rj_value_t;
assign rkd_value = (forward_data1[38] && forward_data1[37] && forward_data1[36:32]==rf_raddr2) ? forward_data1[31:0] : (forward_data2[38] && forward_data2[37] && forward_data2[36:32]==rf_raddr2) ? forward_data2[31:0] :rkd_value_t;
assign src1 = src1_is_pc ? es_pc : rj_value;
assign src2 = src2_is_imm ? imm : src2_is_4 ? 32'h4 : rkd_value;

Alu u_alu (
    .alu_op    (alu_op),
    .alu_src1  (src1),
    .alu_src2  (src2),
    .alu_result(alu_result),
    .zero      (zero),
    .less      (less)
);

MulCon u_mul(
    .valid        (use_mul),
    .is_unsigned  (is_unsigned),
    .use_high     (use_high),
    .src1 (src1),
    .src2   (src2),
    .result       (mul_result)
);

DivCon u_div(
    .valid        (use_div),
    .is_unsigned  (is_unsigned),
    .use_mod      (use_mod),
    .src1     (src1),
    .src2      (src2),
    .result       (div_result)
);


Agu u_agu(
    .clk        (clk),
    .reset      (reset),
    .mem_addr   (alu_result),
    .is_unsigned(is_unsigned),
    .mem_we     (mem_we & ds_to_es_valid),
    .bit_width  (bit_width),
    .mem_rd     (res_from_mem & ds_to_es_valid),
    .src1       (src1),
    .src2       (src2),  
    .wdata      (rkd_value),
    .mem_result (mem_result),
    .dcache_ok   (dcache_ok),
    .dcache_rdata_bus(dcache_rdata_bus),
    .dcache_wdata_bus(dcache_wdata_bus)
);

BranchCond u_branch (
    .pre_jump(is_jump),
    .may_jump(may_jump),
    .use_rj_value(use_rj_value),
    .use_less(use_less),
    .need_less(need_less),
    .use_zero(use_zero),
    .need_zero(need_zero),
    .less(less),
    .zero(zero),
    .pc(es_pc),
    .rj_value(rj_value),
    .jump_target(jump_target),
    .imm(imm),
    .pre_fail(pre_fail)
);

assign final_result = res_from_mem ? mem_result : use_div ? div_result : use_mul ? mul_result : alu_result;

assign br_bus = reset ? 0 : {pre_fail&&ds_to_es_valid, jump_target};
assign flush_IF = pre_fail&&ds_to_es_valid;
assign flush_ID = pre_fail&&ds_to_es_valid;

endmodule
