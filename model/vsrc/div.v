// Radix-2 SRT divisor
`include "define.vh"
module DIV_top(
    input clk,
    input reset,
    input [`ES_TO_DIV_BUS_MD-1:0] es_to_div_bus1,
    input [`ES_TO_DIV_BUS_MD-1:0] es_to_div_bus2,
    output [`DIV_TO_ES_BUS_MD-1:0] div_to_es_bus
);

    wire use_div1;
    wire use_mod1;
    wire is_unsigned1;
    wire [31:0] x1;
    wire [31:0] y1;

    wire use_div2;
    wire use_mod2;
    wire is_unsigned2;
    wire [31:0] x2;
    wire [31:0] y2;

    reg use_div;
    reg use_mod;
    reg is_unsigned;
    reg [31:0] x;
    reg [31:0] y;
    wire [31:0] div_result;
    wire div_ok;

    assign {use_div1, use_mod1, is_unsigned1, x1, y1} = es_to_div_bus1;
    assign {use_div2, use_mod2, is_unsigned2, x2, y2} = es_to_div_bus2;

    always @(*) begin
        if(use_div1) begin
            use_div = use_div1;
            use_mod = use_mod1;
            is_unsigned = is_unsigned1;
            x = x1;
            y = y1;
        end
        else if(use_div2) begin
            use_div = use_div2;
            use_mod = use_mod2;
            is_unsigned = is_unsigned2;
            x = x2;
            y = y2;
        end 
        else begin
           {use_div, use_mod, is_unsigned, x, y} = 0;
        end 
    end

    assign div_to_es_bus = {div_result,div_ok};

    div u_div(
        .div_clk(clk),
        .reset(reset),
        .div(use_div),
        .div_signed(!is_unsigned),
        .x(x),
        .y(y),
        .use_mod(use_mod),
        .div_result(div_result),
        .div_ok(div_ok)
    );

endmodule

module div (
    input div_clk, reset,
    input div,
    input div_signed,
    input [31:0] x, y,
    input use_mod,
    output [31:0] div_result,
    //output [31:0] s, r,
    output div_ok
);
    wire [31:0] s;
    wire [31:0] r;
    wire complete;
    wire div0_err;
    assign div_result = use_mod ? r : s;
    assign div_ok = complete || !div;

    srt_divider my_srt(
        .srt_clk(div_clk),
        .reset(reset),
        .div(div),
        .div_signed(div_signed),
        .dividend(x), .divisor(y), .Q(s), .rem(r),
        .complete(complete),
        .div_zero_err(div0_err)
    );
    
endmodule

module srt_divider (
    input srt_clk,
    input div,
    input reset,
    input div_signed,
    input [31:0] dividend,
    input [31:0] divisor,
    output reg complete,
    output reg div_zero_err,
    output reg [31:0] Q,
    output reg [31:0] rem
);
    
    // ------------ state machine ----------------//
    reg [1:0] status;
    
    localparam WAITING   = 2'b00;
    localparam NORMALIZE = 2'b01;
    localparam DIVIDING  = 2'b10;
    localparam FINISHED  = 2'b11;
    // -------------------------------------------//

    reg [32:0] S; // 
    reg [32:0] D, mD;
    wire [32:0] SpD  = S + D;
    wire [32:0] SpmD = S + mD;
    reg [5:0] counter, rounds, shifter;
    wire Q_is_neg, S_is_neg, D_is_neg, R_is_neg;
    assign Q_is_neg = div_signed & (dividend[31] ^ divisor[31]);
    assign S_is_neg = div_signed & dividend[31];
    assign D_is_neg = div_signed & divisor[31];
    assign R_is_neg = S_is_neg;
    reg q_sign, rem_sign;
    wire [5:0] s_zero, s_one, d_zero;
    wire [5:0] delta_zero = d_zero - s_zero;
    
    leading0_detector div_s0(
        .data(S[31:0]),
        .zero_count(s_zero)
    );
    leading0_detector norm_d(
        .data({D[31] | D[32], D[30:0]}),
        .zero_count(d_zero)
    );
    
    wire [31:0] ulp = {31'd0, S[32]};
    reg [31:0] posQ, negQ; // on the fly (not used)
    
    initial begin
        status <= WAITING;
        complete <= 1'b0;
        div_zero_err <= 1'b0;
        posQ <= 32'd0;
        negQ <= 32'd0;
    end
    
    always @(posedge srt_clk) begin
        if(reset | complete) begin
            complete <= 1'b0;
            status <= WAITING;
            S  <= 33'd0;
            D  <= 33'd0;
            mD <= 33'd0;
            q_sign  <= 1'b0;
            rem_sign<= 1'b0;
            counter <= 6'd0;
            rounds  <= 6'd0;
            div_zero_err <= 1'b0;
            posQ <= 32'd0;
            negQ <= 32'd0;
        end else if(div) begin
            case(status)
                WAITING: begin 
                    status <= NORMALIZE;
                    S <= S_is_neg ? {1'b0, -dividend} : {1'b0, dividend};
                    D <= D_is_neg ? {1'b0, -divisor } : {1'b0,  divisor};
                    q_sign   <= Q_is_neg;
                    rem_sign <= R_is_neg;
                    complete <= 1'b0;
                    posQ <= 32'd0;
                    negQ <= 32'd0;
                    counter <= 6'd0;
                    rounds  <= 6'd0;
                    div_zero_err <= 1'b0;
                end
                NORMALIZE: begin
                    if(d_zero == 6'd32) begin: divide_zero_error
                        div_zero_err <= 1'b1;
                        complete <= 1'b1;
                        status <= WAITING;
                    end else if (delta_zero[5]) begin
                        complete <= 1'b1;
                        status <= WAITING;
                        rem <= dividend;
                        Q <= 32'd0;
                    end begin
                        S  <= {1'b0  , S    << s_zero};
                        D  <= {D[31] , D    << d_zero};
                        mD <= {~D[31], (-D) << d_zero};
                        posQ    <= 32'd0;
                        negQ    <= 32'd0;
                        shifter <= s_zero;
                        counter <= 6'd0;
                        rounds  <= delta_zero;
                        status  <= DIVIDING;
                    end
                end
                DIVIDING: begin
                    if(counter == rounds) begin
                        case(S[32:31])
                            2'b11: begin
                                posQ <= {posQ[31:0], 1'b0};
                                negQ <= {negQ[31:0], 1'b0};
                            end
                            2'b00: begin
                                posQ <= {posQ[31:0], 1'b0};
                                negQ <= {negQ[31:0], 1'b0};
                            end
                            2'b01: begin: q_1_last
                                S    <= SpmD;
                                posQ <= {posQ[31:0], 1'b1};
                                negQ <= {negQ[31:0], 1'b0};
                            end
                            2'b10: begin: q_m1_last
                                S    <= SpD;
                                posQ <= {posQ[31:0], 1'b0};
                                negQ <= {negQ[31:0], 1'b1};
                            end
                        endcase
                        status <= FINISHED;
                    end else begin
                        counter <= counter + 6'd1;
                        case(S[32:31])
                            2'b11: begin
                                S    <= {S[32:0],    1'b0};
                                posQ <= {posQ[31:0], 1'b0};
                                negQ <= {negQ[31:0], 1'b0};
                            end
                            2'b00: begin
                                S    <= {S[32:0],    1'b0};
                                posQ <= {posQ[31:0], 1'b0};
                                negQ <= {negQ[31:0], 1'b0};
                            end
                            2'b01: begin: q_1
                                S    <= {SpmD[32:0], 1'b0};
                                posQ <= {posQ[31:0], 1'b1};
                                negQ <= {negQ[31:0], 1'b0};
                            end
                            2'b10: begin: q_m1
                                S    <= {SpD[32:0] , 1'b0};
                                posQ <= {posQ[31:0], 1'b0};
                                negQ <= {negQ[31:0], 1'b1};
                            end
                        endcase
                    end
                end
                FINISHED: begin
                    complete <= 1'b1;
                    rem <= rem_sign ? -((S[32] ? (S+D) : S) >> (rounds + shifter)) : ((S[32] ? (S+D) : S) >> (rounds + shifter));
                    Q <= q_sign ? (negQ - posQ + ulp) : (posQ - negQ - ulp);
                    S <= {1'b0, dividend};
                    D <= {1'b0, divisor };
                    mD <= 33'd0;
                    status <= WAITING;
                end
            endcase
        end
    end
    
endmodule

module convert_q ( // on-the-fly converting
    input clk, reset, en, div,
    input cur_p, neg,
    output reg [31:0] A, B
);
    reg [2:0] first;
    initial begin
        first = 1'b0;
        A = 32'd0;
        B = 32'd0;
    end
    
    always @(posedge clk) begin
        if(reset) begin
            first <= 1'b0;
            A <= 32'd0;
            B <= 32'd0;
        end else if(en) begin
            if(first < 3'd2) begin
                first <= first + 3'd1;
                if(cur_p == 1'b1) begin
                    A <= {30'd0, 2'b01};
                    B <= {30'd0, 2'b00};
                end
                else begin
                    A <= {30'd0, 2'b11};
                    B <= {30'd0, 2'b10};
                end
            end else begin
                if(cur_p == 1'b1 && neg == 1'b0) begin
                    A <= (A << 1) + 32'd1;
                    B <= A << 1;
                end else if(cur_p == 1'b0) begin
                    A <= A << 1;
                    B <= (B << 1) + 32'd1;
                end else if(cur_p == 1'b1 && neg == 1'b1) begin
                    A <= (B << 1) + 32'd1;
                    B <= (B << 1);
                end
            end
        end
    end
    
endmodule

module csa_adder_div #(parameter WIDTH = 32)  (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire [WIDTH-1:0] c,
    output wire [WIDTH-1:0] sum,
    output wire [WIDTH-1:0] carry           
);

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : csa
            assign sum[i] = a[i] ^ b[i] ^ c[i];
            assign carry[i] = (a[i] & b[i]) || (a[i] & c[i]) || (b[i] & c[i]);
        end
    endgenerate

endmodule


module leading0_detector(
    input [31:0] data,
    output reg [5:0] zero_count
);

    wire [31:0] x;
    assign x = data;
    
//    leading0_detector_onehot my_ldo(
//        .data(x),
//        .zero_count(zero_idx)
//    );
    always @* begin
    case(x[31:16])
        16'd0: begin // 15~0
            case(x[15:8]) 
                8'd0: begin // 7~0
                    case(x[7:4])
                        4'd0: begin // 3~0
                            case(x[3:2])
                            2'b00: begin // 1~0
                                if(x[1] == 1'b1) zero_count = 6'd30;
                                else if(x[0] == 1'b1) zero_count = 6'd31;
                                else zero_count = 6'd32;
                            end
                            default: begin // 3~2
                                if(x[3] == 1'b1) zero_count = 6'd28;
                                else zero_count = 6'd29;
                            end
                            endcase
                        end
                        default: begin // 7~4
                            case(x[7:6])
                            2'b00: begin // 5~4
                                if(x[5] == 1'b1) zero_count = 6'd26;
                                else zero_count = 6'd27;
                            end
                            default:begin // 7~6
                                if(x[7] == 1'b1) zero_count = 6'd24;
                                else zero_count = 6'd25;
                            end
                            endcase
                        end
                    endcase
                end
                default: begin // 15~8
                    case(x[15:12])
                        4'd0: begin // 11~8
                            case(x[11:10])
                            2'b00: begin // 9~8
                                if(x[9] == 1'b1) zero_count = 6'd22;
                                else zero_count = 6'd23;
                            end
                            default:begin // 11~10
                                if(x[11] == 1'b1) zero_count = 6'd20;
                                else zero_count = 6'd21;
                            end
                            endcase
                        end
                        default: begin// 15~12
                            case(x[15:14])
                            2'b00: begin // 13~12
                                if(x[13] == 1'b1) zero_count = 6'd18;
                                else zero_count = 6'd19;
                            end
                            default:begin // 15~14
                                if(x[15] == 1'b1) zero_count = 6'd16;
                                else zero_count = 6'd17;
                            end
                            endcase
                        end
                    endcase
                end
                
            endcase
        end
        default: begin // 31~16
            case(x[31:24])
                8'd0: begin // 23~16
                    case(x[23:20])
                        4'd0: begin // 19~16
                            case(x[19:18])
                            2'b00: begin // 17~16
                                if(x[17] == 1'b1) zero_count = 6'd14;
                                else zero_count = 6'd15;
                            end
                            default: begin // 19~18
                                if(x[19] == 1'b1) zero_count = 6'd12;
                                else zero_count = 6'd13;
                            end
                            endcase
                        end
                        default: begin// 23~20
                            case(x[23:22])
                            2'b00: begin // 21~20
                                if(x[21] == 1'b1) zero_count = 6'd10;
                                else zero_count = 6'd11;
                            end
                            default:begin // 23~22
                                if(x[23] == 1'b1) zero_count = 6'd8;
                                else zero_count = 6'd9;
                            end
                            endcase
                        end
                    endcase
                end
                default: begin // 31~24
                    case(x[31:28])
                        4'd0: begin// 27~24
                            case(x[27:26])
                            2'b00: begin // 25~24
                                if(x[25] == 1'b1) zero_count = 6'd6;
                                else zero_count = 6'd7;
                            end
                            default:begin // 27~26
                                if(x[27] == 1'b1) zero_count = 6'd4;
                                else zero_count = 6'd5;
                            end
                            endcase
                        end
                        default: begin// 31~28
                            case(x[31:30])
                            2'b00: begin // 29~28
                                if(x[29] == 1'b1) zero_count = 6'd2;
                                else zero_count = 6'd3;
                            end
                            default:begin // 31~30
                                if(x[31] == 1'b1) zero_count = 6'd0;
                                else zero_count = 6'd1;
                            end
                            endcase
                        end
                    endcase
                end
            endcase
        end
    endcase
    end

endmodule

