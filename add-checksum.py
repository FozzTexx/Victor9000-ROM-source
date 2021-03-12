#!/usr/bin/env python3
import argparse
import struct

def build_argparser():
  parser = argparse.ArgumentParser(formatter_class=argparse.ArgumentDefaultsHelpFormatter)
  parser.add_argument("rom", help="input file")
  parser.add_argument("--flag", action="store_true", help="flag to do something")
  return parser

def main():
  args = build_argparser().parse_args()

  with open(args.rom, mode="rb") as file:
    rom = file.read()
  words = list(struct.unpack("H" * ((len(rom)) // 2), rom))

  words[-2] = 0
  checksum = (0x2152 - sum(words)) & 0xffff
  print("Checksum is:", hex(checksum))
  words[-2] = checksum
  ck_rom = struct.pack("H" * len(words), *words)
  with open(args.rom, mode="wb") as file:
    file.write(ck_rom)
  
  return

if __name__ == '__main__':
  exit(main() or 0)
