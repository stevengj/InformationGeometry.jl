

using InformationGeometry

abstract type TemperedDistributions <: ContinuousMultivariateDistribution end
struct Dirac <: TemperedDistributions
    μ::AbstractVector
    Dirac(μ) = new(float.(Unwind(μ)))
end

import Base.length
length(d::TemperedDistributions) = length(d.μ)

import Distributions: insupport, mean, cov, invcov, pdf, logpdf
insupport(d::TemperedDistributions,x::AbstractVector) = length(d) == length(x) && all(isfinite, x)
mean(d::TemperedDistributions) = d.μ
cov(d::TemperedDistributions) = Diagonal(zeros(length(d)))
invcov(d::TemperedDistributions) = Diagonal([Inf for i in 1:length(d)])
pdf(d::TemperedDistributions,x::AbstractVector)::Float64 = x == mean(d) ? 1. : 0.
logpdf(d::TemperedDistributions,x::AbstractVector) = log(pdf(d,x))



struct DataSetExact <: AbstractDataSet
    xdist::Distribution
    ydist::Distribution
    dims::Tuple{Int,Int,Int}
    # InvCov::AbstractMatrix
    # X::AbstractVector
    DataSetExact(DS::DataSet) = DataSetExact(xdata(DS),zeros(length(xdata(DS))*length(xdata(DS)[1])),ydata(DS),sigma(DS))
    DataSetExact(x::AbstractVector,y::AbstractVector) = DataSetExact(x,zeros(length(x)),y,ones(length(y)))
    DataSetExact(x::AbstractVector,y::AbstractVector,yerr::AbstractVector) = DataSetExact(x,zeros(length(x)*length(x[1])),y,yerr)
    function DataSetExact(x::AbstractVector,xSig::AbstractVector,y::AbstractVector,ySig::AbstractVector)
        dims = HealthyData(x,y)
        length(Unwind(xSig)) != xdim(dims)*N(dims) && throw("Problem with x errors.")
        length(Unwind(ySig)) != ydim(dims)*N(dims) && throw("Problem with y errors.")
        if xSig == zeros(length(xSig))
            return new(Dirac(x),product_distribution([Normal(y[i],ySig[i]) for i in 1:length(y)]),dims)
        else
            return new(product_distribution([Normal(x[i],xSig[i]) for i in 1:length(x)]),product_distribution([Normal(y[i],ySig[i]) for i in 1:length(y)]),dims)
        end
    end
    function DataSetExact(x::AbstractVector,xCov::AbstractMatrix,y::AbstractVector,yCov::AbstractMatrix)
        dims = HealthyData(x,y)
        !(length(x) == length(y) == size(xCov,1) == size(yCov,1)) && throw("Vectors must have same length.")
        (!isposdef(Symmetric(xCov)) || !isposdef(Symmetric(yCov))) && throw("Covariance matrices not positive-definite.")
        new(MvNormal(x,xCov),MvNormal(y,yCov),dims)
    end
    DataSetExact(xd::Distribution,yd::Distribution) = DataSetExact(xd,yd,Tuple([length(xd),1,1]))
    function DataSetExact(xd::Distribution,yd::Distribution,dims::Tuple{Int,Int,Int})
        Int(length(xd)/xdim(dims)) == Int(length(yd)/ydim(dims)) == N(dims) && return new(xd,yd,dims)
        throw("Dimensions of distributions are inconsistent with $dims: $xd and $yd.")
    end
end
import InformationGeometry: xdim, ydim, xdata, ydata, sigma, InvCov, loglikelihood, Score

N(dims::Tuple{Int,Int,Int}) = dims[1];             N(DSE::DataSetExact) = N(DSE.dims)
xdim(dims::Tuple{Int,Int,Int}) = dims[2];          xdim(DSE::DataSetExact) = xdim(DSE.dims)
ydim(dims::Tuple{Int,Int,Int}) = dims[3];          ydim(DSE::DataSetExact) = ydim(DSE.dims)

xdist(DSE::DataSetExact) = DSE.xdist
ydist(DSE::DataSetExact) = DSE.ydist


function data(DSE::DataSetExact,F::Function)
    isa(F(DSE),Product) && return [location(F(DSE).v[i]) for i in 1:length(F(DSE))]
    return F(DSE).μ
end
xdata(DSE::DataSetExact) = data(DSE,xdist)
ydata(DSE::DataSetExact) = data(DSE,ydist)

Cov(P::Product) = [P.v[i].σ^2 for i in 1:length(P)] |> diagm
Sigma(P::Distribution) = P.Σ
xSigma(DSE::DataSetExact) = Sigma(xdist(DSE))
ySigma(DSE::DataSetExact) = Sigma(ydist(DSE))

InvCov(P::Product) = [P.v[i].σ^(-2) for i in 1:length(P)] |> diagm
function InvCov(P::Distributions.GenericMvTDist)
    if P.df < 3
        return inv(P.Σ).mat
    else
        return diagm([Inf for i in 1:length(P)])
    end
end
InvCov(P::Distribution) = invcov(P)
# InvCov(DSE::DataSetExact) = InvCov(ydist(DSE))

DataMetric(P::Distribution) = InvCov(P)
function DataMetric(P::Distributions.GenericMvTDist)
    if P.df == 1
        return 0.5 .*InvCov(P)
    else
        println("DataMetric: Don't know what to do for t-distribution with dof=$(P.df), just returning usual inverse covariance matrix.")
        return InvCov(P)
    end
end

LogLike(DSE::DataSetExact,x::AbstractVector,y::AbstractVector) = logpdf(xdist(DSE),x) + logpdf(ydist(DSE),y)

loglikelihood(DSE::DataSetExact,model::Function,θ::Vector{<:Number}) = LogLike(DSE,xdata(DSE),EmbeddingMap(DSE,model,θ))

function Score(DSE::DataSetExact,model::Function,dmodel::Function,θ::Vector{<:Number})
    transpose(EmbeddingMatrix(DSE,dmodel,θ)) * gradlogpdf(ydist(DSE),EmbeddingMap(DSE,model,θ))
end
