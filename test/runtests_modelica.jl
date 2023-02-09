cd(joinpath(@__DIR__,".."))
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

# test only MAT_v4
using Test
# include("../src/MAT.jl")
# include("../src/MAT_v4_Modelica.jl")

const mat1s = "W:/sync/mechgits/library/julia/ConvenientModelica/test/ViseHammer_result_1s/ViseHammer_res.mat"



# The Modelica MATv4 file takes the basic v4 Matrix format and adds some requirments to the contents and ordering of the matrices
# The first matrix, Aclass is narrowly defined 

function isLittleEndian(dtype) :: Bool 
  #The type flag contains an integer whose decimal digits encode storage information. If the integer is represented as MOPT where M is the thousands digit...
  T, P, O, M = digits(dtype; pad=4)
  # @enum numberFormat little=0 big=1 vaxD=2 vaxG=3 cray=4
  return M == 0
end

@testset "isLittleEndian" begin
  @test isLittleEndian(0) == true
  @test isLittleEndian(1000) == false
  @test isLittleEndian(2000) == false
  @test isLittleEndian(3000) == false
end

function dataFormat(type) :: DataType 
  #The type flag contains an integer whose decimal digits encode storage information. If the integer is represented as MOPT where M is the thousands digit...
  T, P, O, M = digits(type; pad=4)
  # @enum dataFormat double=0 single=1 int32=2 int16=3 uint16=4 uint8=5
  if P == 0
    return Float64
  end
  if P == 1
    return Float32
  end
  if P == 2
    return Int32
  end
  if P == 3
    return Int16
  end
  if P == 4
    return UInt16
  end
  if P == 5
    return UInt8
  end
end
@testset "dataFormat" begin
  @test dataFormat(0000) <: Float64
  @test dataFormat(0010) <: Float32
  @test dataFormat(0020) <: Int32
  @test dataFormat(0030) <: Int16
  @test dataFormat(0040) <: UInt16
  @test dataFormat(0050) <: UInt8
end

function typeBytes(type::T)::Int where T<:DataType
  if type == Float64
    return 8
  end
  if type == Float32
    return 4
  end
  if type == Int32
    return 4
  end
  if type == Int16
    return 2
  end
  if type == UInt16
    return 2
  end
  if type == UInt8
    return 1
  end
end
@testset "typeBytes" begin
  @test typeBytes(Int32) == 4
end

struct Aclass
  filepath::String
  isTranspose::Bool
  positionStart::Int
  positionEnd::Int
end

"""
Reads the Aclass matrix, returing if the data is stored binNormal or binTranspose
"""
function readAclass( filepath::String )
  open(filepath, "r", lock=false) do matio
    seekstart(matio) # always start from the start, don't assume the position
    startP = position(matio)

    # The 20-byte header consists of five long (4-byte) integers:
    dtype = 0
    nrows = 0
    ncols = 0
    namelen = 0
    includesImaginary = 0
    try
      dtype, nrows, ncols, includesImaginary, namelen = read!(matio, Vector{Int32}(undef, 5)) # 32bit=4byte * 5 qty
    catch e
      error("caught error $e while reading $filepath")
    end

    if !isLittleEndian(dtype) 
      error("Only the little-endian encoding is implemented, cannot read $filepath")
    end

    nameuint = read!(matio, Vector{UInt8}(undef, namelen)) # read the full namelen to make the pointer ready to read the data
    name = replace(String(nameuint), '\0'=>"")
    if name != "Aclass"
      error("First matrix must be named Aclass, is instead [$name]. This likely means that [$filepath] is not a Modelica MAT v4 file.")
    end

    # real: the Real part of the matrix consists of nrows ∗ ncols numbers in the format specified by the P element of the type flag. The data is stored column-wise such that the second column follows the first column, etc.
    fmt = dataFormat(dtype) # read the format type before reading
    realint = read!(matio, Matrix{UInt8}(undef, nrows,ncols))  

    Aclass1 = replace(String(realint[1,:]), '\0'=>"")
    Aclass2 = replace(String(realint[2,:]), '\0'=>"")
    Aclass3 = replace(String(realint[3,:]), '\0'=>"")
    Aclass4 = replace(String(realint[4,:]), '\0'=>"")
    if Aclass1 == "Atrajectory" && Aclass2 == "1.1" && isempty(Aclass3) && Aclass4 == "binNormal" || Aclass4 == "binTrans"
      return Aclass( filepath, Aclass4 == "binTranspose", startP, position(matio) )
    end
  end #open
end

@testset "Aclass" begin
  mat1s = "W:/sync/mechgits/library/julia/ConvenientModelica/test/ViseHammer_result_1s/ViseHammer_res.mat"
  ac = readAclass(mat1s)
  @test ac.positionStart == 0
  @test ac.positionEnd == 71
end


##### the NAME matrix########################################################################################################################
struct VariableNames
  # names::Vector{T}(undef,undef) where T<:AbstractString
  names::Vector{String}
  positionStart::Int
  positionEnd::Int
end

function readVariableNames(ac::Aclass)
  open(ac.filepath, "r", lock=false) do matio
    seek(matio, ac.positionEnd) #skip over Aclass
    startP = position(matio)

    #read the matrix header
    # The 20-byte header consists of five long (4-byte) integers:
    dtype = 0
    nrows = 0
    ncols = 0
    namelen = 0
    includesImaginary = 0
    try
      dtype, nrows, ncols, includesImaginary, namelen = read!(matio, Vector{Int32}(undef, 5)) # int32=4byte * 5 = 20byte
    catch e
      error("caught error $e while reading $ac.filepath")
    end

    #read the matrix name
    nameuint = read!(matio, Vector{UInt8}(undef, namelen)) # read the full namelen to make the pointer ready to read the data
    matrixName = replace(String(nameuint), '\0'=>"")
    if matrixName != "name"
      error("trying to read matrix [name] but read [$matrixName]")
    end

    #read the matrix data
    fmt = dataFormat(dtype) # read the format type before reading
    realint = []
    try
      realint = read!(matio, Matrix{fmt}(undef, nrows,ncols))  # UInt8 from P is 8 bytes long
    catch e
      error("caught error $e while reading $ac.filepath")
    end

    #pull the names out of the matrix
    vnames = []
    for i in 1:ncols
      push!(vnames, replace(String(realint[:,i]), '\0'=>"")) # note :,1 = implicit transpose
    end

    return VariableNames(vnames, startP, position(matio))

  end #open
end

@testset "readVariableNames" begin
  mat1s = "W:/sync/mechgits/library/julia/ConvenientModelica/test/ViseHammer_result_1s/ViseHammer_res.mat"
  ac = readAclass(mat1s)
  vn = readVariableNames(ac)
  # @show vn
  @test length(vn.names) == 2490
  @test vn.names[1] == "time"
  @test vn.names[3] == "revolute.w"
  @test vn.names[30] == "der(alignElastoBacklash.frame_a.r_0[1])"
  @test vn.names[2490] == "world.z_label.color[3]"
  @test vn.positionStart == 71
  @test vn.positionEnd == 117126
end

function getVariableIndex(vn::VariableNames, name::String)
  vecAll = findall( x->x==name, vn.names)
  n = length(vecAll)
  
  if isempty(vecAll) == true
    return -1
  else
    if n>1
      error("Found $n instances of variable [$name], but variables should be unique.")
    end
    return vecAll[1] 
  end
end

@testset "getVariableIndex" begin
  mat1s = "W:/sync/mechgits/library/julia/ConvenientModelica/test/ViseHammer_result_1s/ViseHammer_res.mat"
  ac = readAclass(mat1s)
  vn = readVariableNames(ac)
  @test getVariableIndex(vn, vn.names[3]) == 3
  @test getVariableIndex(vn, vn.names[30]) == 30
end

struct VariableDescriptions
  names::Vector{String}
  descriptions::Vector{String}
  positionStart::Int
  positionEnd::Int
end

function readVariableDescriptions(ac::Aclass, vn::VariableNames)
   open(ac.filepath, "r", lock=false) do matio
    seek(matio, vn.positionEnd) #this follows the VariableNames matrix
    startP = position(matio)

    # The 20-byte header consists of five long (4-byte) integers:
    dtype = 0
    nrows = 0
    ncols = 0
    namelen = 0
    includesImaginary = 0
    try
      dtype, nrows, ncols, includesImaginary, namelen = read!(matio, Vector{Int32}(undef, 5)) # int32=4byte * 5 = 20byte
    catch e
      error("caught error $e while reading $ac.filepath")
    end

    #read the matrix name
    nameuint = read!(matio, Vector{UInt8}(undef, namelen)) # read the full namelen to make the pointer ready to read the data
    matrixName = replace(String(nameuint), '\0'=>"")
    if matrixName != "description"
      error("trying to read matrix [description] but read [$matrixName]")
    end

    #read the matrix data
    fmt = dataFormat(dtype) # read the format type before reading
    realread = []
    try
      realread = read!(matio, Matrix{fmt}(undef, nrows,ncols))  # UInt8 from P is 8 bytes long
    catch e
      error("caught error $e while reading $ac.filepath")
    end

    vdesc = []
    for i in 1:ncols
      push!(vdesc, replace(String(realread[:,i]), '\0'=>"")) # note :,1 = implicit transpose
    end

    return VariableDescriptions(vn.names, vdesc, startP, position(matio))
  end #open
end

@testset "readVariableDescriptions" begin
  mat1s = "W:/sync/mechgits/library/julia/ConvenientModelica/test/ViseHammer_result_1s/ViseHammer_res.mat"
  ac = readAclass(mat1s)
  vn = readVariableNames(ac)
  vd = readVariableDescriptions(ac,vn)
  @test length(vd.descriptions) == 2490  
  @test vd.descriptions[1] == "Simulation time [s]"
  @test vd.descriptions[3] == "First derivative of angle phi (relative angular velocity) [rad/s]"
  @test vd.descriptions[30] == "Position vector from world frame to the connector frame origin, resolved in world frame"
  @test vd.descriptions[2490] == "Color of cylinders"
end

struct DataInfo
  info
  positionStart::Int
  positionEnd::Int
end

"""
dataInfo provides indicies to access variable data

dataInfo
Is an n x 4 integer matrix containing information for each variable (in the same order as the name and description matrices).
  dataInfo(i,1) is 1 or 2, saying if variable i is stored in the data_1 or data_2 matrix. If it is 0, it is the abscissa (time variable).
  dataInfo(i,2) contains the index in the data_1 or data_2 matrix. The index is 1-based and may contain several variables pointing to the same row (alias variables). A negative value means that the variable is a negated alias variable.
  dataInfo(i,3) is 0 to signify linear interpolation. In other tools the value is the number of times differentiable this variable is, which may improve plotting.
  dataInfo(i,4) is -1 in OpenModelica to signify that the value is not defined outside the time range. 0 keeps the first/last value when going outside the time range and 1 performs linear interpolation on the first/last two points.
"""
function readDataInfo(ac::Aclass, vd::VariableDescriptions)
   open(ac.filepath, "r", lock=false) do matio
    seek(matio, vd.positionEnd) #this follows the VariableNames matrix
    startP = position(matio)

    # The 20-byte header consists of five long (4-byte) integers:
    dtype = 0
    nrows = 0
    ncols = 0
    namelen = 0
    includesImaginary = 0
    try
      dtype, nrows, ncols, includesImaginary, namelen = read!(matio, Vector{Int32}(undef, 5)) # int32=4byte * 5 = 20byte
    catch e
      error("caught error $e while reading $ac.filepath")
    end

    #read the matrix name
    nameuint = read!(matio, Vector{UInt8}(undef, namelen)) # read the full namelen to make the pointer ready to read the data
    matrixName = replace(String(nameuint), '\0'=>"")
    if matrixName != "dataInfo"
      error("trying to read variable [dataInfo] but read [$matrixName]")
    end

    #read the matrix data
    fmt = dataFormat(dtype) # read the format type before reading
    realread = []
    try
      realread = read!(matio, Matrix{fmt}(undef, nrows,ncols))  # UInt8 from P is 8 bytes long
    catch e
      error("caught error $e while reading $ac.filepath")
    end

    dinfo = []
    for i in 1:ncols
      push!(dinfo, Dict("name"=>vd.names[i], "description"=>vd.descriptions[i], "locatedInData"=>realread[1,i], "indexInData"=>realread[2,i], "isInterpolated"=>realread[3,i], "isWithinTimeRange"=>realread[4,i] ) )
    end
    return DataInfo( dinfo, startP, position(matio))
  end #open
end


@testset "readDataInfo" begin
  mat1s = "W:/sync/mechgits/library/julia/ConvenientModelica/test/ViseHammer_result_1s/ViseHammer_res.mat"
  ac = readAclass(mat1s)
  vn = readVariableNames(ac)
  vd = readVariableDescriptions(ac,vn)
  di = readDataInfo(ac,vd)
  # @show di.info[3]
  @test di.info[1]["isWithinTimeRange"] == -1
  @test di.info[3]["locatedInData"] == 2 
  @test di.info[30]["isInterpolated"] == 0
  @test di.info[2490]["isWithinTimeRange"] == 0
end

struct MatrixHeader
  type::Int
  nRows::Int
  nCols::Int
  hasImaginary::Bool
  lName::Int
  name::String
  format::DataType
end
"""
Reads the matix header, assuming matio's position is correct to read the header
"""
function readMatrixHeader!(matio::IOStream) :: MatrixHeader
  dtype = 0
  nrows = 0
  ncols = 0
  namelen = 0
  includesImaginary = 0
  try
    dtype, nrows, ncols, includesImaginary, namelen = read!(matio, Vector{Int32}(undef, 5)) # int32=4byte * 5 = 20byte
  catch e
    error("caught error $e while reading matrix header")
  end

  # data1MatrixName = mark(matio)
  nameuint = read!(matio, Vector{UInt8}(undef, namelen)) # read the full namelen to make the pointer ready to read the data
  matrixName = replace(String(nameuint), '\0'=>"")

  fmt = dataFormat(dtype) # read the format type before reading

  return MatrixHeader(dtype,nrows,ncols,includesImaginary,namelen,matrixName, fmt)
end

"""
read one variable from the thing
to read a variable, we need its index, then to look up whether it is in data_1 or data_2
"""
function readVariable(ac::Aclass, vn::VariableNames, vd::VariableDescriptions, di::DataInfo, name::String)
  display(ac)
  
  open(ac.filepath, "r", lock=false) do matio
    seek(matio, di.positionEnd) #this follows the VariableNames matrix

    println("\ndata_1:")
    # read data1 header:
    data1HeaderStart = mark(matio)
    # dtype = 0
    # nrows = 0
    # ncols = 0
    # namelen = 0
    # includesImaginary = 0
    # try
    #   dtype, nrows, ncols, includesImaginary, namelen = read!(matio, Vector{Int32}(undef, 5)) # int32=4byte * 5 = 20byte
    # catch e
    #   error("caught error $e while reading $ac.filepath")
    # end
    # mh1 = MatrixHeader(dtype,nrows,ncols,includesImaginary,namelen)
    mh1 = readMatrixHeader!(matio)
    if mh1.name != "data_1"
      error("trying to read matrix [data_1] but read $matrixName")
    end

    # data1MatrixName = mark(matio)
    # nameuint = read!(matio, Vector{UInt8}(undef, mh1.lName)) # read the full namelen to make the pointer ready to read the data
    # matrixName = replace(String(nameuint), '\0'=>"")
    # if matrixName != "data_1"
    #   error("trying to read matrix [data_1] but read $matrixName")
    # end

    #skip dataMatrix1
    data1MatrixStart = mark(matio)
    # fmt1 = dataFormat(mh1.type) # read the format type before reading
    try
      toskip = mh1.nRows*mh1.nCols*typeBytes(mh1.format) #817*2*8 = 13072, 488197+20+7+13072 = 501296
      skip(matio, toskip )
    catch e
      error("caught error $e while reading $ac.filepath")
    end

    # read data2 header:
    println("\ndata_2:")
    # dtype = 0
    # nrows = 0
    # ncols = 0
    # namelen = 0
    # includesImaginary = 0
    # try
    #   dtype, nrows, ncols, includesImaginary, namelen = read!(matio, Vector{Int32}(undef, 5)) # int32=4byte * 5 = 20byte
    # catch e
    #   error("caught error $e while reading $ac.filepath")
    # end
    # # mh2 = MatrixHeader(dtype,nrows,ncols,includesImaginary,namelen)

    # #read the matrix name
    # data2MatrixName = mark(matio)
    # nameuint = read!(matio, Vector{UInt8}(undef, namelen)) # read the full namelen to make the pointer ready to read the data
    # matrixName = replace(String(nameuint), '\0'=>"")
    mh2 = readMatrixHeader!(matio)

    if mh2.name != "data_2"
      error("trying to read matrix [data_2] but read $(mh2.name)")
    end
    data2MatrixStart = mark(matio)

    #with the positions marked, read the desired variable
    # println("\nlocate variable [$name]:")
    varInd = getVariableIndex(vn, name)

    if di.info[varInd]["locatedInData"] == 1 #data_1
      #read the matrix data_1
      # fmt1 = dataFormat(dtype) # read the format type before reading
      # @show di.info[varInd]

      # dataInfo(i,4) is -1 in OpenModelica to signify that the value is not defined outside the time range. 0 keeps the first/last value when going outside the time range and 1 performs linear interpolation on the first/last two points.
      if di.info[varInd]["isWithinTimeRange"]== 0 #linear interpolation
        # seek(matio, data1MatrixStart)
        # realread = read!(matio, Vector{mh1.format}(undef,10))
        # display(realread)
        #data format is: time(tInitial), var1(tI), ... varN(tI), time(tFinal), var1(tF), ... varN(tF)
        # seek(matio, data1MatrixStart + (di.info[varInd]["indexInData"]-1)*typeBytes(mh1.format) + ((ind-1)*nrows*typeBytes(mh1.format)) )
        # readns[ind] = read(matio, mh1.format)

        readns = Vector{mh1.format}(undef, mh1.nCols)
        for ind = 1:mh1.nCols
          seek(matio, data1MatrixStart + (di.info[varInd]["indexInData"]-1)*typeBytes(mh1.format) + ((ind-1)*mh1.nRows*typeBytes(mh1.format)) )
          readns[ind] = read(matio, mh1.format)
        end
        return readns
      end

    elseif name == "time" || di.info[varInd]["locatedInData"] == 2 #data_2
      #read the matrix data_2
      # fmt2 = dataFormat(dtype) # read the format type before reading

      if ac.isTranspose == false
        # data is sequential: time(t0), var1(t0), var2(t0),... varN(t0), time(t1), var1(t1),...
        readns = Vector{mh2.format}(undef, mh2.nCols)
        for ind = 1:mh2.nCols
          seek(matio, data2MatrixStart + (di.info[varInd]["indexInData"]-1)*typeBytes(mh2.format) + ((ind-1)*mh2.nRows*typeBytes(mh2.format)) )
          readns[ind] = read(matio, mh2.format)
        end
        return readns
      else
        error("reading binTranspose not implemented, lack test data")
      end
    else
      error("variable [$name] is located in an unknown location")
    end
  end #open
end

using JSON
@testset "readVariable" begin
  # mat1s = "W:/sync/mechgits/library/julia/ConvenientModelica/test/ViseHammer_result_1s/ViseHammer_res.mat"
  matbb = "W:/sync/mechgits/library/julia/MAT.jl/test/Modelica/BouncingBall/BouncingBall_res.mat"
  ac = readAclass(matbb)
  vn = readVariableNames(ac)
  vd = readVariableDescriptions(ac,vn)
  di = readDataInfo(ac,vd)

  # println(JSON.json(di.info, 2)) #get the data 1/2 info

  eff = readVariable(ac, vn, vd, di, "eff") #data1
  @test length(eff) == 2
  @test eff[1] ≈ 0.77
  @test eff[2] ≈ 0.77

  grav = readVariable(ac, vn, vd, di, "grav") #data1
  @test length(grav) == 2
  @test grav[1] ≈ 9.81
  @test grav[2] ≈ 9.81

  time = readVariable(ac, vn, vd, di, "time") # data0
  @test all(isapprox.(time, [0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1,1], rtol=1e-3))

  height = readVariable(ac, vn, vd, di, "height") #data2
  @test isapprox(height[1], 111, rtol=1e-3)
  @test isapprox(height[2], 110.9509, rtol=1e-3)

  vel = readVariable(ac, vn, vd, di, "vel") #data2
  @test isapprox(vel[2], -0.981, rtol=1e-3)
end


;
