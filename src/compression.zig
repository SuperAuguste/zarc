const std = @import("std");

pub const CompressionMethod = enum(u16) {
    none = 0,
    shrunk = 1,
    rwcf1 = 2,
    rwcf2 = 3,
    rwcf3 = 4,
    rwcf4 = 5,
    imploded = 6,
    deflated = 8,
    enhanced_deflated = 9,
    pkware_dcl_imploded = 10,
    bzip2 = 12,
    lzma = 14,
    ibm_terse = 18,
    ibm_lz77_z = 19,
    ppmd_version_i_rev_1 = 98,
};
