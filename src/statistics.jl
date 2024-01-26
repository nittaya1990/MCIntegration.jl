"""
    struct Result{O,C}

the returned result of the MC integration.

# Members

- `mean`: mean of the MC integration
- `stdev`: standard deviation of the MC integration samples
- `chi2`: reduced chi-square of the MC integration samples
- `neval`: number of evaluations of the integrand
- `ignore`: ignore iterations untill `ignore`
- `config`: configuration of the MC integration from the last iteration
- `iterations`: list of tuples [(data, error, Configuration), ...] from each iteration
"""
struct Result{O,C}
    mean::Vector{O}
    stdev::Vector{O}
    chi2::Any
    neval::Int
    ignore::Int # ignore iterations untill ignore_iter
    config::C
    iterations::Any
    function Result(history::AbstractVector, ignore::Int)
        # history[end][1] # a vector of avg
        # history[end][2] # a vector of std
        # history[end][3] # a vector of config
        init = ignore + 1
        @assert length(history) > 0
        config = history[end][3]
        # dof = (length(history) - init + 1) - 1 # number of effective samples - 1
        neval = sum(h[3].neval for h in history)
        @assert config.N >= 1
        # if config.N == 1
        #     O = typeof(history[end][1][1]) #if there is only value, then extract this value from the vector
        #     mean, stdev, chi2 = average(history, 1; init=init, max=length(history))
        # else
        # O = typeof(history[end][1])
        # @assert O <: AbstractVector
        mean, stdev, chi2 = [], [], []
        res = [average(history, o; init=init, max=length(history)) for o in 1:config.N]
        mean = [r[1] for r in res]
        stdev = [r[2] for r in res]
        chi2 = [r[3] for r in res]
        # for o in 1:config.N
        #     _mean, _stdev, _chi2 = average(history, dof + 1, o)
        #     push!(mean, _mean)
        #     push!(stdev, _stdev)
        #     push!(chi2, _chi2)
        # end
        # end
        # println(mean, ", ", stdev, ", ", chi2)
        # println(typeof(mean), typeof(config))
        return new{eltype(mean),typeof(config)}(mean, stdev, chi2, neval, ignore, config, history)
    end
    function Result(res::Result, ignore::Int)
        if ignore == res.ignore
            return res
        else
            return Result(res.iterations, ignore)
        end
    end
end

function dof(result::Result)
    init = result.ignore + 1
    return (length(result.iterations) - init + 1) - 1 # number of effective samples - 1
end

function Base.getindex(result::Result, idx::Int)
    return result.mean[idx], result.stdev[idx], result.chi2[idx]
end

function sig_digits(err)
    if err == 0
        return 0
    else
        return max(0, 2 - floor(Int, log10(abs(err))))
    end
end

function format_number(val, ndigits)
    s = string(round(val, digits=ndigits))
    # println(s)
    return s
end

function tostring(mval, merr; pm="±")
    # println(mval, ", ", merr)

    if mval isa Real && merr isa Real && isfinite(mval) && isfinite(merr)
        m = @sprintf("%24.8g %s %-24.8g", mval, pm, merr)
        # m = measurement(mval, merr)
        # return @sprintf("$m")
    elseif mval isa Complex && merr isa Complex && isfinite(mval) && isfinite(merr)
        # m = @sprintf("%16.6g(%6g) + %16.6g(%6g)im", real(mval), real(merr), imag(mval), imag(merr))
        # m = measurement(real(mval), real(merr)) + measurement(imag(mval), imag(merr)) * 1im
        # return @sprintf("%16.6g(%6g) + %16.6g(%6g)im", real(mval), real(merr), imag(mval), imag(merr))
        # m = @sprintf("(%16.6g %s %6g) + (%16.6g %s %6g)im", real(mval), pm, real(merr), imag(mval), pm, imag(merr))
        real_ndigits = sig_digits(real(merr))
        imag_ndigits = sig_digits(imag(merr))
        # ndigits = maximum([real_ndigits, imag_ndigits])
        # println(real_ndigits, ", ", imag_ndigits)
        realstr = "$(format_number(real(mval), real_ndigits))($(format_number(real(merr), real_ndigits)))"
        imagstr = "$(format_number(real(mval), imag_ndigits))($(format_number(real(merr), imag_ndigits))) im"
        m = @sprintf("%24s + %-24s", realstr, imagstr)

        # m = "$(format_number(real(mval), real_ndigits))($(format_number(real(merr), real_ndigits)))+$(format_number(imag(mval), imag_ndigits))($(format_number(imag(merr), imag_ndigits)))im"
        # m = "$(format_number(real(mval), ndigits))($(first_two_sig_digits_str(real(merr)))) + $(format_number(imag(mval), ndigits))($(first_two_sig_digits_str(imag(merr))))im"
    else
        m = "$mval $pm $merr"
    end

    return "$m"
end

function Base.show(io::IO, result::Result)
    # print(io, summary(result.config))
    # print(io, report(result; verbose=-1, io = io))
    for i in 1:result.config.N
        info = "$i"
        m, e, chi2 = first(result.mean[i]), first(result.stdev[i]), first(result.chi2[i])
        if dof(result) == 0
            print(io, green("Integral $info = $m ± $e"))
        else
            print(io, green("Integral $info = $m ± $e   (reduced chi2 = $(round(chi2, sigdigits=3)))"))
        end
        if i < result.config.N
            print(io, "\n")
        end
    end
end

function Base.show(io::IO, ::MIME"text/plain", result::Result)
    Base.show(io, result)
end

"""
    function report(result::Result, ignore=result.ignore; pick::Union{Function,AbstractVector}=obs -> first(obs), name=nothing, verbose=0, io::IO=Base.stdout)

print the summary of the result. 
It will first print the configuration from the last iteration, then print the weighted average and standard deviation of the picked observable from each iteration.

# Arguments
- `result`: Result object contains the history from each iteration
- `ignore`: ignore the first # iterations.
- `pick`: The pick function is used to select one of the observable to be printed. The return value of pick function must be a Number.
- `name`: name of each picked observable. If name is not given, the index of the pick function will be used.
"""
function report(result::Result, ignore=result.ignore; pick::Union{Function,AbstractVector}=obs -> first(obs), name=nothing, verbose=0, io::IO=Base.stdout)
    if isnothing(name) == false
        name = collect(name)
    end
    ignore_iter = ignore

    for i in 1:result.config.N
        p = pick
        info = isnothing(name) ? "$i" : "$(name[i])"
        if verbose >= 0
            # barbar = "==============================================     Integral $info    =========================================================="
            # bar = "---------------------------------------------------------------------------------------------------------------------------"
            barbar = "================================================     Integral $info    ============================================================"
            bar = "-------------------------------------------------------------------------------------------------------------------------------"
            println(io, barbar)
            println(io, yellow(@sprintf("%6s                 %-32s                 %-32s %22s", "iter", "         integral", "        wgt average", "reduced chi2")))
            println(io, bar)
            for iter in 1:length(result.iterations)
                m0, e0 = p(result.iterations[iter][1][i]), p(result.iterations[iter][2][i])
                m, e, chi2 = average(result.iterations, i; init=ignore_iter + 1, max=iter)
                m, e, chi2 = p(m), p(e), p(chi2)
                iterstr = iter <= ignore_iter ? "ignore" : "$iter"
                sm0, sm = tostring(m0, e0), tostring(m, e)
                println(io, @sprintf("%6s %36s %36s %16.4f", iterstr, sm0, sm, abs(chi2)))
            end
            println(io, bar)
        else
            m, e, chi2 = p(result.mean[i]), p(result.stdev[i]), p(result.chi2[i])
            if dof(result) == 0
                println(io, green("Integral $info = $m ± $e"))
            else
                println(io, green("Integral $info = $m ± $e   (reduced chi2 = $(round(chi2, sigdigits=3)))"))
            end
        end
    end
end

"""

    function average(history, idx=1; init=1, max=length(history))

Average the history[1:max]. Return the mean, standard deviation and chi2 of the history.

# Arguments
- `history`: a list of tuples, such as [(data, error, Configuration), ...]
- `idx`: the index of the integral
- `max`: the last index of the history to average with
- `init` : the first index of the history to average with
"""
function average(history, idx=1; init=1, max=length(history))
    @assert max > 0
    @assert init > 0
    if max <= init
        return history[1][1][idx], history[1][2][idx], zero(history[1][1][idx])
    end

    function _statistic(data, weight)
        @assert length(data) == length(weight)
        # println(data, " and ", weight)
        weightsum = sum(weight)
        mea = sum(data[i] .* weight[i] ./ weightsum for i in eachindex(weight))
        err = 1.0 ./ sqrt.(weightsum)
        if max > 1
            chi2 = sum(weight[i] .* (data[i] - mea) .^ 2 for i in eachindex(weight))
        else
            chi2 = zero(mea)
        end
        return mea, err, chi2 / ((max - init + 1) - 1)
    end

    if eltype(history[end][1][idx]) <: Complex
        dataR = [real.(history[i][1][idx]) for i in init:max]
        dataI = [imag.(history[i][1][idx]) for i in init:max]
        weightR = [1.0 ./ (real.(history[i][2][idx]) .+ 1.0e-10) .^ 2 for i in init:max]
        weightI = [1.0 ./ (imag.(history[i][2][idx]) .+ 1.0e-10) .^ 2 for i in init:max]
        mR, eR, chi2R = _statistic(dataR, weightR)
        mI, eI, chi2I = _statistic(dataI, weightI)
        return mR + mI * 1im, eR + eI * 1im, chi2R + chi2I * 1im
    else
        data = [history[i][1][idx] for i in init:max]
        weight = [1.0 ./ (history[i][2][idx] .+ 1.0e-10) .^ 2 for i in init:max]
        return _statistic(data, weight)
    end
end