using FortranFiles
using Base.Test
using Compat.Iterators: product

import FortranFiles: RecordMarkerType, AccessMode, SequentialAccess, DirectAccess

# To test long records being split into subrecords, without needing
# test data files of several GB, define a custom RecordMarkerType with
# a short maximum subrecord length
const maxsubreclen = 2^15 - 9
const RECMRK4Bwssr = FortranFiles.WithSubrecords(maxsubreclen)
const RECMRK4Bwosr = FortranFiles.WithoutSubrecords{Int32}()
const nelem        = 73
const dareclen     = nelem*sizeof(Complex128)

# --- Definition of different types of record marker ---

immutable RecordTypeTest
   rectyp :: Any
   desc   :: String
   target :: String
   tag    :: String
   fflags :: String
end

const rectyp_tests = [
   RecordTypeTest( DirectAccess, "fixed length (direct access)",
                   "gendatadirect", "DA", "" ),
   RecordTypeTest( RECMRK4Bwssr, "markers of 4-byte with short subrecords",
                   "gendataseq", "4Bshort", "-fmax-subrecord-length=$(maxsubreclen)" ),
   RecordTypeTest( RECMRK4B, "markers of 4-byte with default subrecords",
                   "gendataseq", "4Bdef", "" ),
   RecordTypeTest( RECMRK8B, "markers of 8-byte without subrecords",
                   "gendataseq", "8B", "-frecord-marker=8" ),
   RecordTypeTest( RECMRK4Bwosr, "markers of 4-byte without subrecords",
                   "gendataseq", "4Bdumb", "" )
   ]

# --- Definition of different byte order conversions ---

immutable ByteOrderTest
   name   :: String
   tag    :: String
   fflags :: String
end

const byteorder_tests = [
   ByteOrderTest( "native",        "no",   "" ),
   ByteOrderTest( "little-endian", "LE", "-fconvert=little-endian" ),
   ByteOrderTest( "big-endian",    "BE", "-fconvert=big-endian" ),
   ]

# --- Generation of test data and Julia reading/writing code ---

function gendata(target, tag, fflags)
   cmd = `make -C codegen $target SUFFIX=_$tag XFLAGS=$fflags`
   run(cmd)
   cmd = `codegen/$(target)_$(tag).x data_$(tag).bin`
   run(cmd)
end

function genalldata(tests...)
   for test in product(tests...)
      tag = join( (t.tag for t in test), "_" )
      fflags = join( (t.fflags for t in test), " " )
      gendata(test[1].target, tag, fflags)
   end
   return nothing
end

genalldata(rectyp_tests, byteorder_tests)

include("codegen/jread.jl")
include("codegen/jskip.jl")
include("codegen/jwrite.jl")

# --- Auxiliary functions ---

function cmpfiles(a::String, b::String)
   cmd = `cmp $a $b`
   try
      run(cmd)
      return true
   catch
      return false
   end
end

readdata(f::FortranFile{DirectAccess}) = _readdata(f, nelem)
skipdata(f::FortranFile{DirectAccess}) = _readdata(f, 1)

function _readdata(f, n::Integer)
   vari1  = read(f, rec=1,  Array{Int8}(n))
   @test typeof(vari1)==Array{Int8,1}
   @test sizeof(vari1)==sizeof(Int8)*n
   vari2  = read(f, rec=2,  Array{Int16}(n))
   @test typeof(vari2)==Array{Int16,1}
   @test sizeof(vari2)==sizeof(Int16)*n
   vari4  = read(f, rec=3,  Array{Int32}(n))
   @test typeof(vari4)==Array{Int32,1}
   @test sizeof(vari4)==sizeof(Int32)*n
   vari8  = read(f, rec=4,  Array{Int64}(n))
   @test typeof(vari8)==Array{Int64,1}
   @test sizeof(vari8)==sizeof(Int64)*n
   varr4  = read(f, rec=11, Array{Float32}(n))
   @test typeof(varr4)==Array{Float32,1}
   @test sizeof(varr4)==sizeof(Float32)*n
   varr8  = read(f, rec=12, Array{Float64}(n))
   @test typeof(varr8)==Array{Float64,1}
   @test sizeof(varr8)==sizeof(Float64)*n
   varc8  = read(f, rec=21, Array{Complex64}(n))
   @test typeof(varc8)==Array{Complex64,1}
   @test sizeof(varc8)==sizeof(Complex64)*n
   varc16 = read(f, rec=22, Array{Complex128}(n))
   @test typeof(varc16)==Array{Complex128,1}
   @test sizeof(varc16)==sizeof(Complex128)*n
   varstr = read(f, rec=30,  Array{FString{11}}(n))
   @test typeof(varstr)==Array{FString{11},1}
   @test sizeof(varstr)==sizeof(FString{11})*n
   return ( vari1, vari2, vari4, vari8, varr4, varr8, varc8, varc16, varstr )
end

function writedata(f::FortranFile{DirectAccess}, data)
   vari1, vari2, vari4, vari8, varr4, varr8, varc8, varc16, varstr = data
   nwritten = write(f, rec=1,  vari1)
   @test nwritten==sizeof(vari1)
   nwritten = write(f, rec=2,  vari2)
   @test nwritten==sizeof(vari2)
   nwritten = write(f, rec=3,  vari4)
   @test nwritten==sizeof(vari4)
   nwritten = write(f, rec=4,  vari8)
   @test nwritten==sizeof(vari8)
   nwritten = write(f, rec=11, varr4)
   @test nwritten==sizeof(varr4)
   nwritten = write(f, rec=12, varr8)
   @test nwritten==sizeof(varr8)
   nwritten = write(f, rec=21, varc8)
   @test nwritten==sizeof(varc8)
   nwritten = write(f, rec=22, varc16)
   @test nwritten==sizeof(varc16)
   nwritten = write(f, rec=30, varstr)
   @test nwritten==sizeof(varstr)
   # going back
   nwritten = write(f, rec=16, varc16)
   @test nwritten==sizeof(varc16)
   # overwriting
   nwritten = write(f, rec=16, varstr)
   @test nwritten==sizeof(varstr)
end


# --- TESTING STARTS HERE ---

@testset "Strings" begin
   jstr = "Hello World!"
   N    = length(jstr)
   fstr = FString(N, jstr)
   @test typeof(fstr) == FString{N}
   @test trimstring(fstr) == jstr
   fstr = FString(80, jstr)
   @test typeof(fstr) == FString{80}
   @test trimstring(fstr) == jstr
   fstr = FString(8, jstr)
   @test typeof(fstr) == FString{8}
   @test trimstring(fstr) == jstr[1:8]
   jstr = "Hällo Wörld!"
   @test_throws InexactError FString(80, jstr)
end

@testset "Testing records with $(rectest.desc), $(botest.name) byte order" for rectest in rectyp_tests, botest in byteorder_tests

   local infile, outfile, data
   tag = "$(rectest.tag)_$(botest.tag)"
   infilename  = "data_$(tag).bin"
   outfilename = "chck_$(tag).bin"

   @testset "Opening files" begin
      if isa(rectest.rectyp, RecordMarkerType)
         infile  = FortranFile(infilename, "r", marker = rectest.rectyp, convert = botest.name)
         @test infile.acctyp.recmrktyp == rectest.rectyp
         outfile = FortranFile(outfilename, "w", marker = rectest.rectyp, convert = botest.name)
         @test outfile.acctyp.recmrktyp == rectest.rectyp
      else
         infile  = FortranFile(infilename, "r", access="direct", recl=dareclen, convert = botest.name)
         @test infile.acctyp.reclen == dareclen
         outfile = FortranFile(outfilename, "w", access="direct", recl=dareclen, convert = botest.name)
         @test infile.acctyp.reclen == dareclen
      end
   end

   @time @testset "Reading data" begin
      data = readdata(infile)
   end

   @time @testset "Reading data with skipping" begin
      rewind(infile)
      skipdata(infile)
      close(infile)
   end

   @time @testset "Writing data" begin
      writedata(outfile, data)
      close(outfile)
   end

   @testset "Verifying data" begin
      @test cmpfiles(infilename, outfilename)
   end

end;
