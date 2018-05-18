
# each entry consist of
# [ name, packed, numeric_formats ]
# flat expansion yields to vulkan non-compressed formats in the same order
formatData = [
    [ "R4_G4",              True,   [ "uNorm" ] ],
    [ "R4_G4_B4_A4",        True,   [ "uNorm" ] ],
    [ "B4_G4_R4_A4",        True,   [ "uNorm" ] ],
    [ "R5_G6_B5",           True,   [ "uNorm" ] ],
    [ "B5_G6_R5",           True,   [ "uNorm" ] ],
    [ "R5_G5_B5_A1",        True,   [ "uNorm" ] ],
    [ "B5_G5_R5_A1",        True,   [ "uNorm" ] ],
    [ "A1_R5_G5_B5",        True,   [ "uNorm" ] ],
    [ "R8",                 False,  [ "uNorm",    "sNorm",
                                      "uScaled",  "sScaled",
                                      "uInt",     "sInt",     "sRgb" ] ],
    [ "R8_G8",              False,  [ "uNorm",    "sNorm",
                                      "uScaled",  "sScaled",
                                      "uInt",     "sInt",     "sRgb" ] ],
    [ "R8_G8_B8",           False,  [ "uNorm",    "sNorm",
                                      "uScaled",  "sScaled",
                                      "uInt",     "sInt",     "sRgb" ] ],
    [ "B8_G8_R8",           False,  [ "uNorm",    "sNorm",
                                      "uScaled",  "sScaled",
                                      "uInt",     "sInt",     "sRgb" ] ],
    [ "R8_G8_B8_A8",        False,  [ "uNorm",    "sNorm",
                                      "uScaled",  "sScaled",
                                      "uInt",     "sInt",     "sRgb" ] ],
    [ "B8_G8_R8_A8",        False,  [ "uNorm",    "sNorm",
                                      "uScaled",  "sScaled",
                                      "uInt",     "sInt",     "sRgb" ] ],
    [ "A8_B8_G8_R8",        True,   [ "uNorm",    "sNorm",
                                      "uScaled",  "sScaled",
                                      "uInt",     "sInt",     "sRgb" ] ],
    [ "A2_R10_G10_B10",     True,   [ "uNorm",    "sNorm",
                                      "uScaled",  "sScaled",
                                      "uInt",     "sInt" ] ],
    [ "A2_B10_G10_R10",     True,   [ "uNorm",    "sNorm",
                                      "uScaled",  "sScaled",
                                      "uInt",     "sInt" ] ],
    [ "R16",                False,  [ "uNorm",    "sNorm",
                                      "uScaled",  "sScaled",
                                      "uInt",     "sInt",     "sFloat" ] ],
    [ "R16_G16",            False,  [ "uNorm",    "sNorm",
                                      "uScaled",  "sScaled",
                                      "uInt",     "sInt",     "sFloat" ] ],
    [ "R16_G16_B16",        False,  [ "uNorm",    "sNorm",
                                      "uScaled",  "sScaled",
                                      "uInt",     "sInt",     "sFloat" ] ],
    [ "R16_G16_B16_A16",    False,  [ "uNorm",    "sNorm",
                                      "uScaled",  "sScaled",
                                      "uInt",     "sInt",     "sFloat" ] ],
    [ "R32",                False,  [ "uInt",     "sInt",     "sFloat" ] ],
    [ "R32_G32",            False,  [ "uInt",     "sInt",     "sFloat" ] ],
    [ "R32_G32_B32",        False,  [ "uInt",     "sInt",     "sFloat" ] ],
    [ "R32_G32_B32_A32",    False,  [ "uInt",     "sInt",     "sFloat" ] ],
    [ "R64",                False,  [ "uInt",     "sInt",     "sFloat" ] ],
    [ "R64_G64",            False,  [ "uInt",     "sInt",     "sFloat" ] ],
    [ "R64_G64_B64",        False,  [ "uInt",     "sInt",     "sFloat" ] ],
    [ "R64_G64_B64_A64",    False,  [ "uInt",     "sInt",     "sFloat" ] ],
    [ "B10_G11_R11",        True,   [ "uFloat" ] ],
    [ "E5_B9_G9_R9",        True,   [ "uFloat" ] ],
    [ "D16",                False,  [ "uNorm" ] ],
    [ "X8_D24",             True,   [ "uNorm" ] ],
    [ "D32",                False,  [ "sFloat" ] ],
    [ "S8",                 False,  [ "uInt" ] ],
    [ "D16_S8",             False,  [ "uNorm" ] ],  # note: stencil is always uint
    [ "D24_S8",             False,  [ "uNorm" ] ],
    [ "D32_S8",             False,  [ "sFloat" ] ]
]
