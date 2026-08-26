module Gtool3

export GTRecord
export read_gt3
export headerinfo

export read_record
#export mask_missing
export decode_float64

# Header of the gt3.
# See https://www.gfd-dennou.org/library/gtool/gtool3/doc/gtool.pdf
const HEADER_NAMES = [
    "IDFM",
    "DSET",
    "ITEM",
    "EDIT1", "EDIT2", "EDIT3", "EDIT4",
    "EDIT5", "EDIT6", "EDIT7", "EDIT8",
    "FNUM", "DNUM",
    "TITL1", "TITL2",
    "UNIT",
    "ETTL1", "ETTL2", "ETTL3", "ETTL4",
    "ETTL5", "ETTL6", "ETTL7", "ETTL8",
    "TIME",
    "UTIM",
    "DATE",
    "TDUR",
    "AITM1", "ASTR1", "AEND1",
    "AITM2", "ASTR2", "AEND2",
    "AITM3", "ASTR3", "AEND3",
    "DFMT", "MISS",
    "DMIN", "DMAX", "DIVS", "DIVL",
    "STYP",
    "OPT1", "OPT2", "OPT3",
    "MEMO1", "MEMO2", "MEMO3", "MEMO4",
    "MEMO5", "MEMO6", "MEMO7", "MEMO8",
    "MEMO9", "MEMO10", "MEMO11", "MEMO12",
    "CDATE", "CSIGN", "MDATE", "MSIGN",
    "SIZE"
]

# Container of a 3-D data
struct GTRecord{T}
    header::Dict{String,String}
    data::Array{T,3}
end

# byte b[4] -> Uint32 value
function uint32_from_bytes(b::AbstractVector{UInt8}, endian::Symbol)
    @assert length(b) == 4
    if endian == :big
        return (UInt32(b[1]) << 24) |
               (UInt32(b[2]) << 16) |
               (UInt32(b[3]) << 8)  |
               UInt32(b[4])
    elseif endian == :little
        return UInt32(b[1]) |
               (UInt32(b[2]) << 8) |
               (UInt32(b[3]) << 16) |
               (UInt32(b[4]) << 24)
    else
        error("endian must be :big or :little")
    end
end

# byte b[8] -> Uint64 value
function uint64_from_bytes(b::AbstractVector{UInt8}, endian::Symbol)
    @assert length(b) == 8
    x = UInt64(0)
    if endian == :big
        for v in b
            x = (x << 8) | UInt64(v)
        end
    elseif endian == :little
        for i in 8:-1:1
            x = (x << 8) | UInt64(b[i])
        end
    else
        error("endian must be :big or :little")
    end
    return x
end

# read 4 bytes (for sequential access mode)
function read_marker(io, endian::Symbol)
    b = read(io, 4)
    length(b) == 4 || error("Unexpected EOF while reading record marker")
    return Int(uint32_from_bytes(b, endian))
end

# read one data in sequential access mode
function read_record(io, endian::Symbol)
    # first 4-byte
    n1 = read_marker(io, endian)
    # data
    data = read(io, n1)
    length(data) == n1 || error("Unexpected EOF inside Fortran record")
    # last 4-byte: must be same as the first 4-byte
    n2 = read_marker(io, endian)
    n1 == n2 || error("Fortran record markers disagree: $n1 != $n2")
    return data
end

clean_string(b) = strip(replace(String(b), '\0' => ""))

function parse_header(buf::AbstractVector{UInt8})
    length(buf) == 1024 || error("GTOOL3 header must be 1024 bytes")
    h = Dict{String,String}()
    for i in 1:64
        j1 = 16 * (i - 1) + 1
        j2 = 16 * i
        h[HEADER_NAMES[i]] = clean_string(buf[j1:j2])
    end
    return h
end

function intfield(h, name)
    s = strip(h[name])
    isempty(s) && error("Empty integer header field: $name")
    return parse(Int, s)
end

function dimensions(h)
    nx = intfield(h, "AEND1") - intfield(h, "ASTR1") + 1
    ny = intfield(h, "AEND2") - intfield(h, "ASTR2") + 1
    nz = intfield(h, "AEND3") - intfield(h, "ASTR3") + 1
    return nx, ny, nz
end

function decode_float32(buf::AbstractVector{UInt8}, endian::Symbol)
    length(buf) % 4 == 0 || error("Float32 record length is not a multiple of 4")
    n = length(buf) ÷ 4
    x = Vector{Float32}(undef, n)
    for i in 1:n
        k = 4 * (i - 1) + 1
        u = uint32_from_bytes(@view(buf[k:k+3]), endian)
        x[i] = reinterpret(Float32, u)
    end
    return x
end

function decode_float64(buf::AbstractVector{UInt8}, endian::Symbol)
    length(buf) % 8 == 0 || error("Float64 record length is not a multiple of 8")
    n = length(buf) ÷ 8
    x = Vector{Float64}(undef, n)
    for i in 1:n
        k = 8 * (i - 1) + 1
        u = uint64_from_bytes(@view(buf[k:k+7]), endian)
        x[i] = reinterpret(Float64, u)
    end
    return x
end

# determine
#   sequential/other access
#   big/little endian
# Note: ssume gtool3 has 1024 bytes headers (it is always valid for gtool3)
function detect_gt3_format(io)
    pos = position(io)
    b = read(io, 4)
    seek(io, pos)
    length(b) == 4 || error("File is too short")
    n_be = Int(uint32_from_bytes(b, :big))
    n_le = Int(uint32_from_bytes(b, :little))
    if n_be == 1024
        return true, :big
    elseif n_le == 1024
        return true, :little
    else
        return false, :big
    end
end

function element_size(h)
    fmt = uppercase(strip(h["DFMT"]))
    if fmt == "UR4" || fmt == "UR"
        return 4
    elseif fmt == "UR8"
        return 8
    else
        error("Unsupported GTOOL3 DFMT: $fmt")
    end
end

function decode_data(buf, h, endian)
    fmt = uppercase(strip(h["DFMT"]))
    if fmt == "UR4" || fmt == "UR"
        return decode_float32(buf, endian)
    elseif fmt == "UR8"
        return decode_float64(buf, endian)
    else
        error("Unsupported GTOOL3 DFMT: $fmt")
    end
end

function read_gt3(filename::AbstractString;
                  endian::Symbol=:auto,
                  sequential::Symbol=:auto,
                  missing_replacement=NaN)
    
    records = GTRecord[]
    open(filename, "r") do io
        detected_seq, detected_endian = detect_gt3_format(io)
        seq = sequential == :auto ? detected_seq    : sequential
        en  =     endian == :auto ? detected_endian : endian

        while !eof(io)
            # read header
            hbuf = seq ? read_record(io, en) : read(io, 1024)
            isempty(hbuf) && break
            length(hbuf) == 1024 || error("Invalid GTOOL3 header size: $(length(hbuf))")
            h = parse_header(hbuf)
            nx, ny, nz = dimensions(h)
            nbyte = nx * ny * nz * element_size(h)
            
            # read data
            dbuf = seq ? read_record(io, en) : read(io, nbyte)
            length(dbuf) == nbyte || error("Data size mismatch: expected $nbyte, got $(length(dbuf))")
            x = decode_data(dbuf, h, en)
            a = reshape(x, nx, ny, nz)

            # replace missing values with missing_replacement
            s = strip(h["MISS"])
            if ! isempty(s)
                miss = parse(Float64, replace(s, 'D' => 'E', 'd' => 'e'))
                a[a .== miss] .= missing_replacement
            end

            # save header and data
            push!(records, GTRecord(h, a))
        end
    end
    
    return records  # records[i]: i-th header and data
end


function mask_missing(r::GTRecord; replacement=NaN)
    a = Float64.(r.data)
    s = strip(r.header["MISS"])
    isempty(s) && return a
    miss = parse(Float64, replace(s, 'D' => 'E', 'd' => 'e'))
    a[a .== miss] .= replacement
    return a
end

"""
    headerinfo(r::GTRecord)

Print a summary of the header and data dimensions of `r` to standard output.

The summary contains the dataset and item names, title, unit, time, date, data
format, missing value, axis names and ranges, header size, and the shape of the
data array. Returns `nothing`.
"""
function headerinfo(r::GTRecord)
    h = r.header
    println("DSET  : ", h["DSET"])
    println("ITEM  : ", h["ITEM"])
    println("TITLE : ", strip(h["TITL1"] * h["TITL2"]))
    println("UNIT  : ", h["UNIT"])
    println("TIME  : ", h["TIME"], " ", h["UTIM"])
    println("DATE  : ", h["DATE"])
    println("DFMT  : ", h["DFMT"])
    println("MISS  : ", h["MISS"])
    println("AITM1 : ", repr(h["AITM1"]), "  ", h["ASTR1"], ":", h["AEND1"])
    println("AITM2 : ", repr(h["AITM2"]), "  ", h["ASTR2"], ":", h["AEND2"])
    println("AITM3 : ", repr(h["AITM3"]), "  ", h["ASTR3"], ":", h["AEND3"])
    println("SIZE  : ", h["SIZE"], " ", size(r.data))
end

end # module Gtool3

