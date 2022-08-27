"""
Example from Cuba.jl documentation: https://giordano.github.io/Cuba.jl/stable/#One-dimensional-integral-1
Integral log(x)/sqrt(x) in [0, 1), expected to be -4
Evaluated 1e5 times

Cuba: -3.9964946185407024 ± 0.0014907251005373207
Vegas classic: -3.99078(68)
Vegas+hypercube redistribution: -3.99908(39)

Both MCIntegration and Kristjan's vegas fail this example
"""

using Cuba
using MCIntegration
# using Plots
using PyCall
# using PythonCall
Vegas = pyimport("vegas")

function f1(x)
    return log(x[1]) / sqrt(x[1])
end

# x = LinRange(0.0, 1.0, 100)
# plot(x, f1.(x))

result = vegas((x, f) -> f[1] = f1(x[1]), maxevals=1e4)
@time result = vegas((x, f) -> f[1] = f1(x[1]), maxevals=1e5)

integ = Vegas.Integrator([[0, 1],])
result = integ(f1, nitn=10, neval=1e4, beta=0.0)

integ2 = Vegas.Integrator([[0, 1],])
result = integ2(f1, nitn=10, neval=1e4)
println(result.summary())
println("result = $(result), Q = $(result.Q)")

function integrand(c)
    return f1(c.var[1][1])
end
result = integrate(c -> (f1(c.var[1][1])), neval=1e3, niter=10)
@time result = integrate(integrand, neval=1e3, niter=10, print=-1)

# X = Continuous(0.0, 1.0, grid=collect(LinRange(0.0, 1.0, 1000)), adapt=false)
# @time result = integrate(c -> (f1(c.var[1][1])), var=(X,), neval=1e6, niter=50, print=0)