
### Confidence Regions


One of the primary goals of [**InformationGeometry.jl**](https://github.com/RafaelArutjunjan/InformationGeometry.jl) is to enable the user to investigate the relationships between different parameters in a model in detail by determining and visualizing the **exact** confidence regions associated with the best fit parameters. In this context, *exact* refers to the fact that no simplifying assumptions are made about the shape of the confidence regions.

```@setup 1
using InformationGeometry, Plots; gr() # hide
DS = DataSet([1,2,3,4], [4,5,6.5,9], [0.5,0.45,0.6,1]) # hide
model(x::Real, θ::AbstractVector{<:Real}) = θ[1] * x + θ[2] # hide
DM = DataModel(DS, model) # hide
# p = FittedPlot(DM) # hide
# savefig(p, "../assets/CR-FittedPlot.svg"); nothing # hide
```
```julia
DS = DataSet([1,2,3,4], [4,5,6.5,9], [0.5,0.45,0.6,1])
model(x::Real, θ::AbstractVector{<:Real}) = θ[1] * x + θ[2]
DM = DataModel(DS, model)
FittedPlot(DM)
```
![](https://raw.githubusercontent.com/RafaelArutjunjan/InformationGeometry.jl/master/docs/assets/CR-FittedPlot.svg)

Depending on how the parameters ``\theta`` enter into the model, the shapes of confidence regions associated with the model may be distorted. For the linearly parametrized model ``y_\text{model}(x;\theta) = \theta_1 \cdot x + \theta_2`` from above, the ``1 \sigma`` and ``2 \sigma`` confidence regions form perfect ellipses around the maximum likelihood estimate as expected:
```@setup 1
# sols = ConfidenceRegions(DM, 1:2; tol=1e-9) # hide
# scatter([MLE(DM)[1]],[MLE(DM)[2]],marker=:c,label="MLE") # hide
# plot!(sols[1],vars=(1,2),label="1σ CR",title="Confidence Regions for linearly parametrized model", xlabel="θ[1]", ylabel="θ[2]") # hide
# plot!(sols[2],vars=(1,2),label="2σ CR") # hide
# savefig("../assets/sols.svg"); nothing # hide
```
```julia
sols = ConfidenceRegions(DM, 1:2; tol=1e-9)
VisualizeSols(DM, sols)
```
![](https://raw.githubusercontent.com/RafaelArutjunjan/InformationGeometry.jl/master/docs/assets/sols.svg)


For a non-linearly parametrized model such as ``y_\text{model}(x;\theta) = {\theta_1}^{\!3} \cdot x + \mathrm{exp}(\theta_1 + \theta_2)`` (which also produces a straight line fit!), the confidence regions are no longer ellipsoidal:
```@setup 1
model2(x::Real, θ::AbstractVector{<:Real}) = θ[1]^3 * x + exp(θ[1] + θ[2])
DM2 = DataModel(DS, model2)
sols2 = ConfidenceRegions(DM2, 1:2; tol=1e-9)
# scatter([MLE(DM2)[1]],[MLE(DM2)[2]],marker=:c,label="MLE") # hide
# plot!(sols2[1],vars=(1,2),label="1σ CR",title="Confidence Regions for non-linearly parametrized model", xlabel="θ[1]", ylabel="θ[2]") # hide
# plot!(sols2[2],vars=(1,2),label="2σ CR") # hide
# savefig("../assets/sols2.svg"); nothing # hide
```
```julia
model2(x::Real, θ::AbstractVector{<:Real}) = θ[1]^3 * x + exp(θ[1] + θ[2])
DM2 = DataModel(DS, model2)
sols2 = ConfidenceRegions(DM2, 1:2; tol=1e-9)
VisualizeSols(DM2, sols2)
```
![](https://raw.githubusercontent.com/RafaelArutjunjan/InformationGeometry.jl/master/docs/assets/sols2.svg)

Specifically in the case of two-dimensional parameter spaces as shown here, the problem of finding the exact boundaries of the confidence regions is turned into a system of ordinary differential equations and subsequently solved using the [**DifferentialEquations.jl**](https://github.com/SciML/DifferentialEquations.jl) suite. As a result, the boundaries of the confidence regions are obtained in the form of `ODESolution` objects, which come equipped with elaborate interpolation methods.


Both finding as well as visualizing exact confidence regions for models depending on more than two parameters (i.e. ``\mathrm{dim} \, \mathcal{M} > 2``) is more challenging from a technical perspective. For such models, it is clearly only possible to visualize three-dimensional slices of the parameter space at a time. The easiest way to achieve this is to intersect the confidence region with a family of 2D planes, in which the boundaries of the confidence region are computed using the 2D scheme.

The specific components of ``\theta`` to be visualized can be passed as a tuple to `ConfidenceRegion()` via the keyword argument `Dirs=(1,2,3)`. Also, the keyword `N` can be used to (approximately) control the number of planes with which the confidence region of interest is intersected.

```@setup 1
DM3 = DataModel(DS, (x,θ)-> θ[1]^3 * x + exp(θ[1] + θ[2]) + θ[3] * sin(x))
# Planes, sols3 = ConfidenceRegion(DM3, 1; tol=1e-6, Dirs=(1,2,3), N=50)
# VisualizeSols(DM3, Planes, sols3)
# p = VisualizeSols(InformationGeometry.ModelMappize(DM3), Planes, sols3; title="3D Confidence Region for non-linearly parametrized model") # hide
# savefig(p,"../assets/sols3.svg"); nothing # hide
```
```julia
DM3 = DataModel(DS, (x,θ)-> θ[1]^3 * x + exp(θ[1] + θ[2]) + θ[3] * sin(x))
Planes, sols3 = ConfidenceRegion(DM3, 1; tol=1e-6, Dirs=(1,2,3), N=50)
VisualizeSols(DM3, Planes, sols3)
```
![](https://raw.githubusercontent.com/RafaelArutjunjan/InformationGeometry.jl/master/docs/assets/sols3.svg)

Here, only the ``1\sigma`` confidence region is shown. Given the non-linearity of the model, it is of course no surprise that the region is strongly distorted compared with a perfect ellipsoid.


Once the boundary of a confidence region associated with some particular level has been computed, it can be used to establish the most extreme deviations from the maximum likelihood prediction, which are possible at said confidence level. These can then be illustrated as so-called "pointwise confidence bands" around the best fit. For example, given the confidence boundaries of the model `DM2` from above, the ``2\sigma`` confidence band can be obtained via:
```@setup 1
# FittedPlot(DM2)
# ConfidenceBands(DM2, sols2[2])
# savefig("../assets/Bands.svg"); nothing # hide
```
```julia
FittedPlot(DM2)
ConfidenceBands(DM2, sols2[2])
```
![](https://raw.githubusercontent.com/RafaelArutjunjan/InformationGeometry.jl/master/docs/assets/Bands.svg)

```@docs
ConfidenceRegions(::DataModel,::Vector{Float64})
ConfidenceBands
```
