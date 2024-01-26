module Dist
using StaticArrays
using LinearAlgebra
import ..TINY

# abstract type AdaptiveMap end

# """
#     abstract type Variable end

# Abstract Type of all variable pools. 
# """
# abstract type Variable end
# abstract type ScalarVariable{T} end
abstract type AbstractVectorVariable{T} <: AbstractVector{T} end
# struct MatrixVariable <: Variable end
# struct NonVariable <: Variable end

is_variable(::Type) = false
is_variable(x::T) where {T} = is_variable(T)
is_variable(::Type{<:AbstractVectorVariable}) = true

# basic AbstractArray implement
Base.length(tg::AbstractVectorVariable) = length(tg.data)
Base.size(tg::AbstractVectorVariable) = size(tg.data)
Base.size(tg::AbstractVectorVariable, I::Int) = size(tg.data, I)
Base.getindex(tg::AbstractVectorVariable, I::Int) = tg.data[I]
Base.setindex!(tg::AbstractVectorVariable, v, I::Int) = tg.data[I] = v
Base.firstindex(tg::AbstractVectorVariable) = 1
Base.lastindex(tg::AbstractVectorVariable) = length(tg)

# iterator
Base.iterate(tg::AbstractVectorVariable) = (tg[1], 1)
Base.iterate(tg::AbstractVectorVariable, state) = (state >= length(tg)) ? nothing : (tg[state+1], state + 1)
# Base.IteratorSize(tg)
Base.IteratorSize(::Type{AbstractVectorVariable{GT}}) where {GT} = Base.HasLength()
Base.IteratorEltype(::Type{AbstractVectorVariable{GT}}) where {GT} = Base.HasEltype()
Base.eltype(::Type{AbstractVectorVariable{GT}}) where {GT} = eltype(GT)

Base.show(io::IO, ::MIME"text/plain", obj::AbstractVectorVariable) = Base.show(io, obj)
Base.show(io::IO, ::MIME"text/html", obj::AbstractVectorVariable) = Base.show(io, obj)


function Base.resize!(var::AbstractVectorVariable{GT}, size::Int) where {GT}
    @assert size > length(var) "The new size should be larger than the old size $(length(var))!"
    resize!(var.data, size)
    resize!(var.prob, size)
end

"""
    function poolsize(var::AbstractVectorVariable{GT}) where {GT}

Return the size of the pool of the variable.
"""
function poolsize(var::AbstractVectorVariable{GT}) where {GT}
    return length(var)
end

const MaxOrder = 16

include("common.jl")
include("variable.jl")
include("sampler.jl")
export is_variable
export FermiK
export Continuous
export Discrete
export CompositeVar
export create!, shift!, swap!
export createRollback!, shiftRollback!, swapRollback!
export poolsize
end