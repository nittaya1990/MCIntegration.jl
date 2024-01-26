"""
Example from https://vegas.readthedocs.io/en/latest/tutorial.html#basic-integrals
After 1e6 evaluations

Kristjan' Vegas: 0.9998140106054249 +- 0.0001588395357154431
Vegas plus hypercube redistribution: 1.00025(32)
Cuba: 1.000062449185617 ± 0.0002931183036898656
MCIntegration: 0.9919809055601388 ± 0.006475616264856342
"""

using MCIntegration
using Cuba
using PyCall
Vegas = pyimport("vegas")

function f(x)
    dx2 = 0
    for d in 1:4
        dx2 += (x[d] - 0.5)^2
    end
    return exp(-dx2 * 100.0) * 1013.2118364296088
end

res = integrate((x, c) -> f(x), neval=1e5, dof=[[4],], verbose=-1, solver=:vegas)
println("MCIntegration.jl vegas (Julia): ", res.mean[1], " ± ", res.stdev[1])

res = integrate((x, c) -> f(x), neval=1e5, dof=[[4],], verbose=-1, solver=:vegasmc)
println("MCIntegration.jl vegasmc (Julia): ", res.mean[1], " ± ", res.stdev[1])

result = vegas((x, g) -> g[1] = f(x), 4, maxevals=1e6)
println("Cuba (C): ", result.integral[1], " ± ", result.error[1])

integ = Vegas.Integrator([[0, 1], [0, 1], [0, 1], [0, 1]])
result = integ(f, nitn=10, neval=1e5, beta=0.0)
println("Classic Vegas (Python): ", result)

result = integ(f, nitn=10, neval=1e5)
println("Vegas+ (Python): ", result)

