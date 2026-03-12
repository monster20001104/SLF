import os
import re


def calculate_parity(data_hex, original_width):
    """计算奇偶校验位并扩展数据宽度"""
    data_int = int(data_hex, 16)
    new_width = original_width + (original_width + 7) // 8  # 16->18

    # 计算每个字节的奇偶校验位
    parity_bits = 0
    for i in range((original_width + 7) // 8):
        byte = (data_int >> (i * 8)) & 0xFF
        parity = bin(byte).count('1') % 2
        parity_bits |= parity << (original_width + i)

    # 组合校验位和原始数据
    new_data = parity_bits | data_int
    return f"{new_data:0{(new_width + 3) // 4}X}"


def convert_mif(input_file, output_file=None, replace=False):
    """转换MIF文件"""
    if replace:
        output_file = input_file
        with open(input_file, 'r') as f:
            lines = f.readlines()
        with open(output_file, 'w') as f_out:
            process_lines(lines, f_out)
    else:
        output_file = output_file or f"{os.path.splitext(input_file)[0]}_converted.mif"
        with open(input_file, 'r') as f_in, open(output_file, 'w') as f_out:
            process_lines(f_in, f_out)

    print(f"转换完成，文件已{'替换' if replace else '保存'}为: {output_file}")


def process_lines(input_lines, output_file):
    width = None
    for line in input_lines:
        line = line.strip()
        if line.startswith("WIDTH = "):
            match = re.match(r"WIDTH\s*=\s*(\d+);", line)
            if match:
                width = int(match.group(1))
                new_width = width + (width + 7) // 8
                output_file.write(f"WIDTH = {new_width};\n")
            else:
                output_file.write(f"{line}\n")
        elif ':' in line and ';' in line and width:
            addr, data = line.split(':')
            data_hex = data.split(';')[0].strip()
            new_data = calculate_parity(data_hex, width)
            output_file.write(f"{addr}:{new_data};\n")
        else:
            output_file.write(f"{line}\n")


# 使用示例
if __name__ == "__main__":
    input_file_list = [
        "../../src/virtio2/virtio_rx_buf/virtio_rx_buf_csum_ip256.mif",
        "../../src/virtio2/virtio_rx_buf/virtio_rx_buf_csum_trans256.mif",
        ]  # 添加rom的地址
    # input_file = "../../src/virtio2/virtio_rx_buf/virtio_rx_buf_csum_ip256.mif"  # 替换为你的输入文件路径

    # 模式1: 替换原文件
    # convert_mif(input_file, replace=True)

    # 模式2: 生成新文件(默认)
    for input_file in input_file_list:
        convert_mif(input_file)
