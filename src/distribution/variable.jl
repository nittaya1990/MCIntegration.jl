mutable struct FermiK{D} <: Variable
    # data::Vector{MVector{D,Float64}}
    data::Matrix{Float64}
    # data::Vector{Vector{Float64}}
    kF::Float64
    δk::Float64
    maxK::Float64
    offset::Int
    prob::Vector{Float64}
    histogram::Vector{Float64}
    function FermiK(dim, kF, δk, maxK, size=MaxOrder; offset=0)
        @assert offset + 1 < size
        k = zeros(dim, size) .+ kF / sqrt(dim)
        # k0 = MVector{dim,Float64}([kF for i = 1:dim])
        # k0 = @SVector [kF for i = 1:dim]
        # k = [k0 for i = 1:size]
        prob = ones(size)
        return new{dim}(k, kF, δk, maxK, offset, prob, [0.0,])
    end
end

function Base.show(io::IO, var::FermiK{D}) where {D}
    print(io, ("$(D)D FermiK variable ∈ [0, $(var.maxK)).")
              * (" Max number = $(length(var.data)-1-var.offset).")
              * (var.offset > 0 ? " Offset = $(var.offset)." : "")
    )
end

Base.length(Var::FermiK{D}) where {D} = size(Var.data)[2]
Base.getindex(Var::FermiK{D}, i::Int) where {D} = view(Var.data, :, i)
function Base.setindex!(Var::FermiK{D}, v, i::Int) where {D}
    view(Var.data, :, i) .= v
end
Base.lastindex(Var::FermiK{D}) where {D} = size(Var.data)[2] # return index, not the value

mutable struct RadialFermiK <: Variable
    data::Vector{Float64}
    kF::Float64
    δk::Float64
    offset::Int
    histogram::Vector{Float64}
    function RadialFermiK(kF=1.0, δk=0.01, size=MaxOrder; offset=0)
        @assert offset + 1 < size
        k = [kF * (i - 0.5) / size for i = 1:size] #avoid duplication
        return new(k, kF, δk, offset, [0.0,])
    end
end

### variables that uses a vegas+ algorithm for impotrant sampling ###
# mutable struct Vegas{D,G} <: Variable
#     permutation::Vector{Int}
#     uniform::Matrix{Float64}
#     data::Matrix{Float64}
#     gidx::Vector{Int}
#     offset::Int
#     grid::G

#     width::Vector{Float64}
#     histogram::Vector{Float64}
#     accumulation::Vector{Float64}
#     distribution::Vector{Float64}

#     alpha::Float64
#     beta::Float64
#     adapt::Bool
# end

mutable struct Continuous{G} <: Variable
    data::Vector{Float64}
    gidx::Vector{Int}
    prob::Vector{Float64} # probability of the given variable. For the vegas map, = dy/dx = 1/N/Δxᵢ = inverse of the Jacobian
    lower::Float64
    range::Float64
    offset::Int
    grid::G
    inc::Vector{Float64}
    histogram::Vector{Float64} # length(grid) - 1
    alpha::Float64
    adapt::Bool
end

"""
    function Continuous(lower::Float64, upper::Float64; ninc = 1000, alpha=2.0, adapt=true) where {G}

Create a pool of continous variables sampling from the set [lower, upper) with a distribution generated by a Vegas map (see below). 
The distribution is trained after each iteraction if `adapt = true`.

# Arguments:
- `lower`  : lower bound
- `upper`  : upper bound
- `ninc`   : number of increments
- `alpha`  : learning rate
- `adapt`  : turn on or off the adaptive map

# Remark:
Vegas map maps the original integration variables x into new variables y, so that the integrand is as flat as possible in y:
```math
\\begin{aligned}
x_0 &= a \\\\
x_1 &= x_0 + \\Delta x_0 \\\\
x_2 &= x_1 + \\Delta x_1 \\\\
\\cdots \\\\
x_N &= x_{N-1} + \\Delta x_{N-1} = b
\\end{aligned}
```
where a and b are the limits of integration. The grid specifies the transformation function at the points ``y=i/N`` for ``i=0,1\\ldots N``:
```math
x(y=i/N) = x_i
```

Linear interpolation is used between those points. The Jacobian for this transformation is:
```math
J(y) = J_i = N \\Delta x_i
```

The grid point ``x_i`` is trained after each iteration.
"""
function Continuous(lower::Float64, upper::Float64, size=MaxOrder; offset=0, alpha=2.0, adapt=true, ninc=1000, grid=collect(LinRange(lower, upper, ninc)))
    @assert offset + 1 < size
    size = size + 1 # need one more element as cache for the swap operation
    @assert upper > lower + 2 * eps(1.0)
    t = LinRange(lower + (upper - lower) / size, upper - (upper - lower) / size, size) #avoid duplication


    gidx = [locate(grid, t[i]) for i = 1:size]
    prob = ones(size)

    N = length(grid) - 1
    inc = [grid[i+1] - grid[i] for i in 1:N]
    histogram = ones(N) * TINY

    var = Continuous{typeof(grid)}(t, gidx, prob, lower, upper - lower, offset, grid, inc, histogram, alpha, adapt)
    return var
end

function Base.show(io::IO, var::Continuous)
    print(io, (var.adapt ? "Adaptive" : "Nonadaptive") * " Continuous variable ∈ [$(var.lower), $(var.lower+var.range))."
              * (" Max number = $(length(var.data)-1-var.offset).")
              * (var.adapt ? " Learning rate = $(var.alpha)." : "")
              * (var.offset > 0 ? " Offset = $(var.offset)." : "")
    )
end

function accumulate!(T::Continuous, idx::Int, weight=1.0)
    if T.adapt
        T.histogram[T.gidx[idx]] += weight
    end
end

"""
Vegas adaptive map
"""

function train!(T::Continuous)
    # println("hist:", T.histogram[1:10])
    if T.adapt == false
        return
    end
    # println(T.histogram)
    @assert all(x -> isfinite(x), T.histogram) "histogram should be all finite\n histogram =$(T.histogram[findall(x->(!isfinite(x)), T.histogram)]) at $(findall(x->(!isfinite(x)), T.histogram))"
    @assert all(x -> x > 0, T.histogram) "histogram should be all positive and non-zero\n histogram = $(T.histogram)"
    distribution = smooth(T.histogram, 6.0)
    distribution = rescale(distribution, T.alpha)
    newgrid = similar(T.grid)
    newgrid[1] = T.grid[1]
    newgrid[end] = T.grid[end]

    # See the paper https://arxiv.org/pdf/2009.05112.pdf Eq.(20)-(22).
    j = 0         # self_x index
    acc_f = 0.0   # sum(avg_f) accumulated
    avg_f = distribution
    # amount of acc_f per new increment
    # the Eq.(20) in the original paper use length(T.grid) as the denominator. It is not correct.
    f_ninc = sum(avg_f) / (length(T.grid) - 1)
    for i in 2:length(T.grid)-1
        while acc_f < f_ninc
            j += 1
            acc_f += avg_f[j]
        end
        acc_f -= f_ninc
        newgrid[i] = T.grid[j+1] - (acc_f / avg_f[j]) * (T.grid[j+1] - T.grid[j])
    end
    newgrid[end] = T.grid[end] # make sure the last element is the same as the last element of the original grid
    T.grid = newgrid

    clearStatistics!(T) #remove histogram
end

mutable struct TauPair <: Variable
    data::Vector{MVector{2,Float64}}
    λ::Float64
    β::Float64
    offset::Int
    histogram::Vector{Float64}
    function TauPair(β=1.0, λ=0.5, size=MaxOrder; offset=0)
        @assert offset + 1 < size
        t = [@MVector [β * (i - 0.4) / size, β * (i - 0.6) / size] for i = 1:size] #avoid duplication
        return new(t, λ, β, offset, [0.0,])
    end
end

mutable struct Discrete <: Variable
    data::Vector{Int}
    lower::Int
    upper::Int
    prob::Vector{Float64}
    size::Int
    offset::Int
    histogram::Vector{Float64}
    accumulation::Vector{Float64}
    distribution::Vector{Float64}
    alpha::Float64
    adapt::Bool
end

"""
    function Discrete(lower::Int, upper::Int; distribution=nothing, alpha=2.0, adapt=true)

Create a pool of integer variables sampling from the closed set [lower, lower+1, ..., upper] with the distribution `Discrete.distribution``. 
The distribution is trained after each iteraction if `adapt = true`.

# Arguments:
- `lower`  : lower bound
- `upper`  : upper bound
- `distributin`   : inital distribution 
- `alpha`  : learning rate
- `adapt`  : turn on or off the adaptive map
"""
function Discrete(bound::Union{Tuple{Int,Int},Vector{Int}}, size=MaxOrder; distribution=nothing, offset=0, alpha=2.0, adapt=true)
    return Discrete([bound[0], bound[1]], size; distribution=distribution, offset=offset, alpha=alpha, adapt=adapt)
end
function Discrete(lower::Int, upper::Int, size=MaxOrder; distribution=nothing, offset=0, alpha=2.0, adapt=true)
    @assert offset + 1 < size
    size = size + 1 # need one more element as cache for the swap operation
    d = collect(Iterators.take(Iterators.cycle(lower:upper), size)) #avoid dulication

    @assert upper >= lower
    histogram = ones(upper - lower + 1) * TINY
    if isnothing(distribution)
        distribution = deepcopy(histogram) #very important, makesure histogram is not the same array as the distribution
    else
        @assert all(x -> x >= 0.0, distribution) "distribution should be all non-negative!"
        @assert length(distribution) == length(histogram) "distribution should for the range $lower:$upper, which has the length $(upper-lower+1)"
    end
    distribution ./= sum(distribution)
    accumulation = [sum(distribution[1:i]) for i in 1:length(distribution)]
    accumulation = [0.0, accumulation...] # start with 0.0 and end with 1.0
    @assert (accumulation[1] ≈ 0.0) && (accumulation[end] ≈ 1.0) "$(accumulation)"
    prob = ones(length(d))
    prob /= sum(prob)

    newVar = Discrete(d, lower, upper, prob, upper - lower + 1, offset, histogram,
        accumulation, distribution, alpha, adapt)

    @assert !(newVar.distribution === newVar.histogram) "histogram and distribution must be different array!"
    clearStatistics!(newVar)
    return newVar
end

function Base.show(io::IO, var::Discrete)
    print(io, (var.adapt ? "Adaptive" : "Nonadaptive") * " Discrete variable ∈ [$(var.lower), ..., $(var.upper)]."
              * (" Max number = $(length(var.data)-1-var.offset).")
              * (var.adapt ? " Learning rate = $(var.alpha)." : "")
              * (var.offset > 0 ? " Offset = $(var.offset)." : "")
    )
end

function accumulate!(T::Discrete, idx::Int, weight=1.0)
    if T.adapt
        gidx = T[idx] - T.lower + 1
        T.histogram[gidx] += weight
    end
end
function train!(T::Discrete)
    if T.adapt == false
        return
    end
    distribution = deepcopy(T.histogram)
    distribution = rescale(distribution, T.alpha)
    distribution ./= sum(distribution)
    accumulation = [sum(distribution[1:i]) for i in 1:length(distribution)]
    T.accumulation = [0.0, accumulation...] # start with 0.0 and end with 1.0
    T.distribution = distribution
    @assert (T.accumulation[1] ≈ 0.0) && (T.accumulation[end] ≈ 1.0) "$(T.accumulation)"
    @assert !(T.distribution === T.histogram) "histogram and distribution must be different array!"
    clearStatistics!(T)
end

mutable struct CompositeVar{V} <: Variable
    vars::V
    prob::Vector{Float64}
    offset::Int
    adapt::Bool
    size::Int
    _prob_cache::Float64
end

"""
    function CompositeVar(vargs...; adapt=true)

Create a product of different types of random variables. The bundled variables will be sampled with their producted distribution.

# Arguments:
- `vargs`  : tuple of Variables
- `adapt`  : turn on or off the adaptive map
"""
function CompositeVar(vargs...; adapt=true, offset=0, size=MaxOrder)
    @assert all(v -> (v isa Variable), vargs) "all arguments should variables"
    @assert all(v -> !(v isa CompositeVar), vargs) "CompositeVar arguments not allowed"
    for v in vargs
        v.adapt = adapt
        v.offset = offset
        #TODO: resize all variables
        # @assert length(v) 
    end
    vars = Tuple(v for v in vargs)
    newvar = CompositeVar{typeof(vars)}(vars, ones(size), offset, adapt, size, 1.0)
    return newvar
end

function Base.show(io::IO, var::CompositeVar)
    print(io, (var.adapt ? "Adaptive" : "Nonadaptive") * " Composite variable with $(length(var)) components."
              * (" Max number = $(var.size).")
              * (var.offset > 0 ? " Offset = $(var.offset)." : "")
    )
end

Base.length(vars::CompositeVar) = length(vars.vars)
Base.getindex(vars::CompositeVar, i::Int) = vars.vars[i]
# function Base.setindex!(Var::Variable, v, i::Int)
#     Var.data[i] = v
# end
Base.firstindex(Var::CompositeVar) = 1 # return index, not the value
Base.lastindex(Var::CompositeVar) = length(Var.vars) # return index, not the value

# CompositeVar iterator is equal to the tuple iterator
Base.iterate(cvar::CompositeVar) = Base.iterate(cvar.vars)
Base.iterate(cvar::CompositeVar, state) = Base.iterate(cvar.vars, state)

function accumulate!(vars::CompositeVar, idx, weight)
    for v in vars.vars
        accumulate!(v, idx, weight)
    end
end
function train!(vars::CompositeVar)
    for v in vars.vars
        train!(v)
    end
end

function clearStatistics!(vars::CompositeVar)
    for v in vars.vars
        clearStatistics!(v)
    end
end

function addStatistics!(target::CompositeVar, income::CompositeVar)
    for (vi, v) in enumerate(target.vars)
        addStatistics!(v, income.vars[vi])
    end
end

function initialize!(vars::CompositeVar, config)
    for v in vars.vars
        initialize!(v, config)
    end
    for i = 1+vars.offset:vars.size-2
        vars.prob[i] = 1.0
        for v in vars.vars
            vars.prob[i] *= v.prob[i]
        end
    end
end

# mutable struct ContinuousND{D} <: Variable
#     data::Vector{Float64}
#     lower::Vector{Float64}
#     range::Vector{Float64}
#     offset::Int
#     function ContinuousND{dim}(lower, upper, size=MaxOrder; offset=0) where {dim}
#         if lower isa Number
#             lower = ones(Float64, dim) * lower
#         else
#             @assert length(lower) == dim && eltype(lower) isa Number
#         end
#         if upper isa Number
#             upper = ones(Float64, dim) * upper
#         else
#             @assert length(upper) == dim && eltype(upper) isa Number
#         end
#         @assert offset + 1 < size
#         @assert all(x -> x > 0, upper .- lower)
#         println(lower, ", ", upper)

#         ######## deterministic initialization #####################
#         t = []
#         for i in 1:size
#             for d in 1:dim
#                 # the same value should not appear twice!
#                 init = lower[d] + (upper[d] - lower[d]) * ((i - 1) * dim + d - 0.5) / (size * dim)
#                 @assert lower[d] <= init <= upper[d]
#                 append!(t, init)
#             end
#         end

#         return new{dim}(t, lower, upper .- lower, offset)
#     end
# end

################## API for generic variables #######################

"""
    accumulate!(var::Variable, idx, weight) = nothing

Accumulate a new sample with the a given `weight` for the `idx`-th element of the Variable pool `var`.
"""
accumulate!(var::Variable, idx, weight) = nothing

"""
    train!(Var::Variable)

Train the distribution of the variables in the pool.
"""
train!(Var::Variable) = nothing

"""
    clearStatistics!(T::Variable)

Clear the accumulated samples in the Variable.
"""
clearStatistics!(T::Variable) = fill!(T.histogram, 1.0e-10)

addStatistics!(target::Variable, income::Variable) = (target.histogram .+= income.histogram)

"""
    initialize!(T::Variable, config)

Initialize the variable pool with random variables.
"""
function initialize!(T::Variable, config)
    for i = 1+T.offset:length(T)-2
        create!(T, i, config)
    end
end

"""
    total_probability(config)

Calculate the joint probability of all involved variables of all integrals.
"""
function total_probability(config)
    prob = 1.0
    for (vi, var) in enumerate(config.var)
        offset = var.offset
        for pos = 1:config.maxdof[vi]
            prob *= var.prob[pos+offset]
        end
    end
    if prob < TINY
        @warn "probability is either too small or negative : $(prob)"
    end
    return prob
end

"""
    probability(config, idx)

Calculate the joint probability of all involved variable for the `idx`-th integral.
"""
function probability(config, idx)
    prob = 1.0
    dof = config.dof[idx]
    for (vi, var) in enumerate(config.var)
        offset = var.offset
        for pos = 1:dof[vi]
            prob *= var.prob[pos+offset]
        end
    end
    if prob < TINY
        @warn "probability is either too small or negative : $(prob)"
    end
    return prob
end

"""
    padding_probability(config, idx)

Calculate the joint probability of missing variables for the `idx`-th integral compared to the full variable set.

`padding_probability(config, idx) = total_probability(config) / probability(config, idx)`
"""
function padding_probability(config, idx)
    prob = 1.0
    dof = config.dof[idx]
    for (vi, var) in enumerate(config.var)
        offset = var.offset
        for pos = dof[vi]+1:config.maxdof[vi]
            prob *= var.prob[pos+offset]
        end
    end
    if prob < TINY
        @warn "probability is either too small or negative : $(prob)"
    end
    return prob
end

function delta_probability(config, curr=config.curr; new)
    prob = 1.0
    currdof, newdof = config.dof[curr], config.dof[new]
    for (vi, var) in enumerate(config.var)
        offset = config.var[vi].offset
        if (currdof[vi] < newdof[vi]) # more degrees of freedom
            for pos = currdof[vi]+1:newdof[vi]
                prob /= var.prob[pos+offset]
            end
        elseif (currdof[vi] > newdof[vi]) # less degrees of freedom
            for pos = newdof[vi]+1:currdof[vi]
                prob *= var.prob[pos+offset]
            end
        end
    end
    if prob < TINY
        @warn "probability is either too small or negative : $(prob)"
    end
    return prob
end

Base.length(Var::Variable) = length(Var.data)
Base.getindex(Var::Variable, i::Int) = Var.data[i]
function Base.setindex!(Var::Variable, v, i::Int)
    Var.data[i] = v
end
Base.firstindex(Var::Variable) = 1 # return index, not the value
Base.lastindex(Var::Variable) = length(Var.data) # return index, not the value



# struct Uniform{T,D} <: Model
#     lower::T
#     upper::T
#     function Uniform{T,D}(lower, upper) where {T<:Number,D}
#         return new{T,D}(lower, upper)
#     end
# end

# mutable struct Var{T,D,M} <: Variable
#     data::T
#     model::M
#     offset::Int
#     function Var(model{type,D}::Model, size=MaxOrder; offset=0) where {type<:Number,D}
#         # lower, upper = model.lower, model.upper
#         # k = zeros(type, dim, size + offset)
#         # for i in 1:size
#         #     for d in 1:dim
#         #         init = lower[d] + (upper[d] - lower[d]) * ((i - 1) * dim + d - 0.5) / (size * dim)
#         #         @assert lower[d] <= init <= upper[d]
#         #         k[d, i+offset] = init
#         #     end
#         # end
#         if D == 1
#             data = zeros(type, size)
#         else
#             data = zeros(type, (D, size))
#         end
#         return new{typeof(data),D,typeof(model)}(data, model, offset)
#     end
# end

# Base.getindex(var::Var{T,1,M}, i::Int) where {T,M} = var.data[i]
# function Base.setindex!(var::Var{T,1,M}, v, i::Int) where {T,M}
#     var.data[i] = v
# end
# Base.lastindex(var::Var{T,1,M}) where {T,M} = length(var.data) # return index, not the value

# Base.getindex(var::Var{T,D,M}, i::Int) where {T,D,M} = var.data[:, i]
# function Base.setindex!(var::Var{T,D,M}, v, i::Int) where {T,M}
#     var.data[:, i] = v
# end
# Base.lastindex(var::Var{T,D,M}) where {T,D,M} = size(var.data)[2] # return index, not the value
