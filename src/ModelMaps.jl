


# Callback triggers when Boundaries is `true`.
"""
Container for model functions which carries additional information, e.g. about the parameter domain on which it is valid.
"""
struct ModelMap
    Map::Function
    InDomain::Function
    Domain::Union{Cuboid,Nothing}
    xyp::Tuple{Int,Int,Int}
    pnames::Vector{String}
    StaticOutput::Val
    inplace::Val
    CustomEmbedding::Val
    # Given: Bool-valued domain function
    function ModelMap(model::Function, InDomain::Function, xyp::Tuple{Int,Int,Int}; pnames::Union{Vector{String},Bool}=false)
        ModelMap(model, InDomain, nothing, xyp; pnames=pnames)
    end
    # Given: HyperCube
    function ModelMap(model::Function, Domain::Cuboid, xyp::Union{Tuple{Int,Int,Int},Bool}=false; pnames::Union{Vector{String},Bool}=false)
        # Change this to θ -> true to avoid double checking cuboid. Obviously make sure Boundaries() is constructed using both the function test
        # and the Cuboid test first before changing this.
        InDomain(θ::AbstractVector{<:Number})::Bool = θ ∈ Domain
        xyp isa Bool ? ModelMap(model, InDomain, Domain; pnames=pnames) : ModelMap(model, InDomain, Domain, xyp; pnames=pnames)
    end
    # Given: Function only (potentially) -> Find xyp
    function ModelMap(model::Function, InDomain::Function=θ::AbstractVector{<:Number}->true, Domain::Union{Cuboid,Nothing}=nothing; pnames::Union{Vector{String},Bool}=false)
        xyp = if Domain === nothing
            xlen, plen = GetArgSize(model);     testout = model((xlen < 2 ? 1. : ones(xlen)), GetStartP(plen))
            (xlen, size(testout,1), plen)
        else
            plen = length(Domain);      startp = GetStartP(plen)
            xlen = GetArgLength(x->model(x,startp));    testout = model((xlen < 2 ? 1. : ones(xlen)), startp)
            (xlen, size(testout,1), plen)
        end
        ModelMap(model, InDomain, Domain, xyp; pnames=pnames)
    end
    function ModelMap(model::Function, InDomain::Function, Domain::Union{Cuboid,Nothing}, xyp::Tuple{Int,Int,Int}; pnames::Union{Vector{String},Bool}=false)
        pnames = typeof(pnames) == Bool ? CreateSymbolNames(xyp[3],"θ") : pnames
        StaticOutput = typeof(model((xyp[1] < 2 ? 1. : ones(xyp[1])), ones(xyp[3]))) <: SVector
        ModelMap(model, InDomain, Domain, xyp, pnames, Val(StaticOutput), Val(false), Val(false))
    end
    "Construct new ModelMap from function `F` with data from `M`."
    ModelMap(F::Function, M::ModelMap) = ModelMap(F, M.InDomain, M.Domain, M.xyp, M.pnames, M.StaticOutput, M.inplace, M.CustomEmbedding)
    # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    # Careful with inheriting CustomEmbedding to the Jacobian! For automatically generated dmodels (symbolic or autodiff) it should be OFF!
    function ModelMap(Map::Function, InDomain::Function, Domain::Union{Cuboid,Nothing}, xyp::Tuple{Int,Int,Int},
                        pnames::Vector{String}, StaticOutput::Val, inplace::Val=Val(false), CustomEmbedding::Val=Val(false))
        Domain = Domain === nothing ? FullDomain(xyp[3]) : Domain
        new(Map, InDomain, Domain, xyp, pnames, StaticOutput, inplace, CustomEmbedding)
    end
end
(M::ModelMap)(x, θ::AbstractVector{<:Number}; kwargs...) = M.Map(x, θ; kwargs...)
ModelOrFunction = Union{Function,ModelMap}


function InformNames(M::ModelMap, pnames::Vector{String})
    @assert length(pnames) == M.xyp[3]
    ModelMap(M.Map, M.InDomain, M.Domain, M.xyp, pnames, M.StaticOutput, M.inplace, M.CustomEmbedding)
end


pnames(M::ModelMap) = M.pnames
Domain(M::ModelMap) = M.Domain
isinplace(M::ModelMap) = ValToBool(M.inplace)
iscustom(M::ModelMap) = ValToBool(M.CustomEmbedding)


MakeCustom(F::Function, Domain::Union{Cuboid,Bool,Nothing}=nothing) = Domain isa Cuboid ? MakeCustom(ModelMap(F, Domain)) : MakeCustom(ModelMap(F))
function MakeCustom(M::ModelMap)
    if iscustom(M)
        println("Map already uses custom embedding.")
        return M
    else
        return ModelMap(M.Map, M.InDomain, M.Domain, M.xyp, M.pnames, M.StaticOutput, M.inplace, Val(true))
    end
end
function MakeNonCustom(M::ModelMap)
    if !iscustom(M)
        println("Map already not using custom embedding.")
        return M
    else
        return ModelMap(M.Map, M.InDomain, M.Domain, M.xyp, M.pnames, M.StaticOutput, M.inplace, Val(false))
    end
end


function ModelMap(F::Nothing, M::ModelMap)
    println("ModelMap: Got nothing instead of function to build new ModelMap")
    nothing
end
function CreateSymbolNames(n::Int, base::String="θ")
    n == 1 && return [base]
    D = Dict(string.(0:9) .=> ["₀","₁","₂","₃","₄","₅","₆","₇","₈","₉"])
    base .* [prod(get(D,"$x","Q") for x in string(digit)) for digit in 1:n]
end

pdim(DS::AbstractDataSet, model::ModelMap)::Int = model.xyp[3]
function ModelMappize(DM::AbstractDataModel)
    NewMod = Predictor(DM) isa ModelMap ? Predictor(DM) : ModelMap(Predictor(DM))
    NewdMod = dPredictor(DM) isa ModelMap ? dPredictor(DM) : ModelMap(dPredictor(DM))
    DataModel(Data(DM), NewMod, NewdMod, MLE(DM))
end


function OutsideBoundariesFunction(M::ModelMap)
    OutsideBoundaries(u,t,int)::Bool = !((Res ∈ M.Domain) && M.InDomain(Res))
end


"""
Only works for `DataSet` and `DataSetExact` but will output wrong order of components for `CompositeDataSet`!
"""
function ConcatenateModels(Mods::AbstractVector{<:ModelMap})
    @assert ConsistentElDims((x->x.xyp[1]).(Mods)) > 0 && ConsistentElDims((x->x.xyp[3]).(Mods)) > 0
    if Mods[1].xyp[1] == 1
        function ConcatenatedModel(x::Number, θ::AbstractVector{<:Number}; kwargs...)
            map(model->model(x, θ; kwargs...), Mods) |> Reduction
        end
        EbdMap(model::Function,θ::AbstractVector,woundX::AbstractVector,custom::Val{false}; kwargs...) = Reduction(map(x->model(x,θ; kwargs...), woundX))
        EbdMap(model::Function,θ::AbstractVector,woundX::AbstractVector,custom::Val{true}; kwargs...) = model(woundX, θ; kwargs...)
        function ConcatenatedModel(X::AbstractVector{<:Number}, θ::AbstractVector{<:Number}; kwargs...)
            if any(iscustom, Mods)
                Res = if any(m->m.xyp[2]>1, Mods)
                    map(m->Windup(EbdMap(m.Map, θ, X, m.CustomEmbedding; kwargs...), m.xyp[2]), Mods)
                    # map(m->Windup(EmbeddingMap(DS, m, θ, X), m.xyp[2]), Mods)
                else
                    map(m->EbdMap(m.Map, θ, X, m.CustomEmbedding; kwargs...), Mods)
                    # map(m->EmbeddingMap(DS, m, θ, X), Mods)
                end
                return zip(Res...) |> Iterators.flatten |> collect |> Reduction
            else
                return map(z->ConcatenatedModel(z, θ; kwargs...), X) |> Reduction
            end
        end
        return ModelMap(ConcatenatedModel, reduce(union, (z->z.Domain).(Mods)), (Mods[1].xyp[1], sum((q->q.xyp[2]).(Mods)), Mods[1].xyp[3])) |> MakeCustom
    else
        function NConcatenatedModel(x::AbstractVector{<:Number}, θ::AbstractVector{<:Number}; kwargs...)
            map(model->model(x, θ; kwargs...), Mods) |> Reduction
        end
        function NConcatenatedModel(X::AbstractVector{<:AbstractVector{<:Number}}, θ::AbstractVector{<:Number}; kwargs...)
            if any(iscustom, Mods)
                Res = if any(m->m.xyp[2]>1, Mods)
                    map(m->Windup(EmbeddingMap(DS, m, θ, X), m.xyp[2]), Mods)
                else
                    map(m->EmbeddingMap(DS, m, θ, X), Mods)
                end
                return zip(Res...) |> Iterators.flatten |> collect |> Reduction
            else
                return map(z->NConcatenatedModel(z, θ; kwargs...), X) |> Reduction
            end
        end
        return ModelMap(NConcatenatedModel,reduce(union, (z->z.Domain).(Mods)), (Mods[1].xyp[1], sum((q->q.xyp[2]).(Mods)), Mods[1].xyp[3])) |> MakeCustom
    end
end



_Apply(x::AbstractVector{<:Number}, Componentwise::Function, idxs::BoolVector) = [(idxs[i] ? Componentwise(x[i]) : x[i]) for i in eachindex(idxs)]
_ApplyFull(x::AbstractVector{<:Number}, Vectorial::Function) = Vectorial(x)

MonotoneIncreasing(F::Function, Interval::Tuple{Number,Number})::Bool = Monotonicity(F, Interval) == :increasing
MonotoneDecreasing(F::Function, Interval::Tuple{Number,Number})::Bool = Monotonicity(F, Interval) == :decreasing
function Monotonicity(F::Function, Interval::Tuple{Number,Number})
    derivs = map(x->ForwardDiff.derivative(F, x), range(Interval[1], Interval[2]; length=200))
    all(x-> x≥0., derivs) && return :increasing
    all(x-> x≤0., derivs) && return :decreasing
    :neither
end

Transform(model::Function, idxs::BoolVector, Transform::Function, InverseTransform::Function=x->invert(Transform,x)) = _Transform(model, idxs, Transform, InverseTransform)

# Try to do a bit of inference for the new domain here!
function Transform(M::ModelMap, idxs::BoolVector, Transform::Function, InverseTransform::Function=x->invert(Transform,x))
    TransformedDomain(θ::AbstractVector{<:Number}) = M.InDomain(_Apply(θ, Transform, idxs))
    mono = Monotonicity(Transform, (1e-12,50.))
    NewCube = if mono == :increasing
        HyperCube(_Apply(M.Domain.L, InverseTransform, idxs), _Apply(M.Domain.U, InverseTransform, idxs))
    elseif mono == :decreasing
        println("Detected monotone decreasing transformation.")
        HyperCube(_Apply(M.Domain.U, InverseTransform, idxs), _Apply(M.Domain.L, InverseTransform, idxs))
    else
        @warn "Transformation does not appear to be monotone. Unable to infer new Domain."
        FullDomain(length(idxs))
    end
    ModelMap(_Transform(M.Map, idxs, Transform, InverseTransform), TransformedDomain, NewCube,
                        M.xyp, M.pnames, M.StaticOutput, M.inplace, M.CustomEmbedding)
end
# function Transform(M::ModelMap, Transform::Function, InverseTransform::Function=x->invert(Transform,x))
#     Transform(M, trues(M.xyp[3]), Transform, InverseTransform)
# end


function _Transform(F::Function, idxs::BoolVector, Transform::Function, InverseTransform::Function)
    function TransformedModel(x::Union{Number, AbstractVector{<:Number}}, θ::AbstractVector{<:Number}; kwargs...)
        F(x, _Apply(θ, Transform, idxs); kwargs...)
    end
end


"""
    Transform(DM::AbstractDataModel, F::Function, idxs=trues(pdim(DM))) -> DataModel
    Transform(model::Function, idxs, F::Function) -> Function
Transforms the parameters of the model by the given scalar function `F` such that `newmodel(x, θ) = oldmodel(x, F.(θ))`.
By providing `idxs`, one may restrict the application of the function `F` to specific parameter components.
"""
function Transform(DM::AbstractDataModel, F::Function, idxs::BoolVector=trues(pdim(DM)))
    @assert length(idxs) == pdim(DM)
    sum(idxs) == 0 && return DM
    DataModel(Data(DM), Transform(Predictor(DM), idxs, F), _Apply(MLE(DM), x->invert(F,x), idxs))
end
function Transform(DM::AbstractDataModel, F::Function, inverseF::Function, idxs::BoolVector=trues(pdim(DM)))
    @assert length(idxs) == pdim(DM)
    sum(idxs) == 0 && return DM
    DataModel(Data(DM), Transform(Predictor(DM), idxs, F, inverseF), _Apply(MLE(DM), inverseF, idxs))
end


LogTransform(M::ModelOrFunction, idxs::BoolVector=(M isa ModelMap ? trues(M.xyp[3]) : trues(GetArgSize(M)[2]))) = Transform(M, idxs, log, exp)
LogTransform(DM::AbstractDataModel, idxs::BoolVector=trues(pdim(DM))) = Transform(DM, log, exp, idxs)

ExpTransform(M::ModelOrFunction, idxs::BoolVector=(M isa ModelMap ? trues(M.xyp[3]) : trues(GetArgSize(M)[2]))) = Transform(M, idxs, exp, log)
ExpTransform(DM::AbstractDataModel, idxs::BoolVector=trues(pdim(DM))) = Transform(DM, exp, log, idxs)

Log10Transform(M::ModelOrFunction, idxs::BoolVector=(M isa ModelMap ? trues(M.xyp[3]) : trues(GetArgSize(M)[2]))) = Transform(M, idxs, log10, x->10^x)
Log10Transform(DM::AbstractDataModel, idxs::BoolVector=trues(pdim(DM))) = Transform(DM, log10, x->10^x, idxs)

Power10Transform(M::ModelOrFunction, idxs::BoolVector=(M isa ModelMap ? trues(M.xyp[3]) : trues(GetArgSize(M)[2]))) = Transform(M, idxs, x->10^x, log10)
Power10Transform(DM::AbstractDataModel, idxs::BoolVector=trues(pdim(DM))) = Transform(DM, x->10^x, log10, idxs)

ReflectionTransform(M::ModelOrFunction, idxs::BoolVector=(M isa ModelMap ? trues(M.xyp[3]) : trues(GetArgSize(M)[2]))) = Transform(M, idxs, x-> -x, x-> -x)
ReflectionTransform(DM::AbstractDataModel, idxs::BoolVector=trues(pdim(DM))) = Transform(DM, x-> -x, x-> -x, idxs)

ScaleTransform(M::ModelOrFunction, factor::Number, idxs::BoolVector=(M isa ModelMap ? trues(M.xyp[3]) : trues(GetArgSize(M)[2]))) = Transform(M, idxs, x->factor*x, x->x/factor)
ScaleTransform(DM::AbstractDataModel, factor::Number, idxs::BoolVector=trues(pdim(DM))) = Transform(DM, x->factor*x, x->x/factor, idxs)


function TranslationTransform(F::Function, v::AbstractVector{<:Number})
    TranslatedModel(x, θ::AbstractVector{<:Number}; kwargs...) = F(x, θ + v; kwargs...)
end
function TranslationTransform(M::ModelMap, v::AbstractVector{<:Number})
    @assert length(M.Domain) == length(v)
    ModelMap(TranslationTransform(M.Map, v), θ->M.InDomain(θ + v), TranslateCube(M.Domain, -v), M.xyp, M.pnames, M.StaticOutput,
                                    M.inplace, M.CustomEmbedding)
end
function TranslationTransform(DM::AbstractDataModel, v::AbstractVector{<:Number})
    @assert pdim(DM) == length(v)
    DataModel(Data(DM), TranslationTransform(Predictor(DM), v), MLE(DM)-v)
end


function LinearTransform(F::Function, A::AbstractMatrix{<:Number})
    TransformedModel(x, θ::AbstractVector{<:Number}; kwargs...) = F(x, A*θ; kwargs...)
end
function LinearTransform(M::ModelMap, A::AbstractMatrix{<:Number})
    @assert length(M.Domain) == size(A,1) == size(A,2)
    Ainv = inv(A)
    ModelMap(LinearTransform(M.Map, A), θ->M.InDomain(A*θ), HyperCube(Ainv * M.Domain.L, Ainv * M.Domain.U),
                    M.xyp, M.pnames, M.StaticOutput, M.inplace, M.CustomEmbedding)
end
function LinearTransform(DM::AbstractDataModel, A::AbstractMatrix{<:Number})
    @assert pdim(DM) == size(A,1) == size(A,2)
    DataModel(Data(DM), LinearTransform(Predictor(DM), A), inv(A)*MLE(DM))
end


function AffineTransform(F::Function, A::AbstractMatrix{<:Number}, v::AbstractVector{<:Number})
    @assert size(A,1) == size(A,2) == length(v)
    TranslatedModel(x, θ::AbstractVector{<:Number}; kwargs...) = F(x, A*θ + v; kwargs...)
end
function AffineTransform(M::ModelMap, A::AbstractMatrix{<:Number}, v::AbstractVector{<:Number})
    @assert length(M.Domain) == size(A,1) == size(A,2) == length(v)
    Ainv = inv(A)
    ModelMap(AffineTransform(M.Map, A, v), θ->M.InDomain(A*θ+v), HyperCube(Ainv*(M.Domain.L-v), Ainv*(M.Domain.U-v)),
                    M.xyp, M.pnames, M.StaticOutput, M.inplace, M.CustomEmbedding)
end
function AffineTransform(DM::AbstractDataModel, A::AbstractMatrix{<:Number}, v::AbstractVector{<:Number})
    @assert pdim(DM) == size(A,1) == size(A,2) == length(v)
    Ainv = inv(A)
    DataModel(Data(DM), AffineTransform(Predictor(DM), A, v), Ainv*(MLE(DM)-v))
end

LinearDecorrelation(DM::AbstractDataModel) = AffineTransform(DM, cholesky(Symmetric(inv(FisherMetric(DM, MLE(DM))))).L, MLE(DM))


"""
    EmbedModelVia(model, F::Function; Domain::HyperCube=FullDomain(GetArgLength(F))) -> Union{Function,ModelMap}
Transforms a model function via `newmodel(x, θ) = oldmodel(x, F(θ))`.
A `Domain` for the new model can optionally be specified for `ModelMap`s.
"""
function EmbedModelVia(model::Function, F::Function; Kwargs...)
    EmbeddedModel(x, θ; kwargs...) = model(x, F(θ); kwargs...)
end
function EmbedModelVia(M::ModelMap, F::Function; Domain::HyperCube=FullDomain(GetArgLength(F)))
    ModelMap(EmbedModelVia(M.Map, F), (M.InDomain∘F), Domain, (M.xyp[1], M.xyp[2], length(Domain)), CreateSymbolNames(length(Domain), "θ"), M.StaticOutput, M.inplace, M.CustomEmbedding)
end
function EmbedDModelVia(dmodel::Function, F::Function; Kwargs...)
    EmbeddedJacobian(x, θ; kwargs...) = dmodel(x, F(θ); kwargs...) * ForwardDiff.jacobian(F, θ)
end
function EmbedDModelVia(dM::ModelMap, F::Function; Domain::HyperCube=FullDomain(GetArgLength(F)))
    ModelMap(EmbedDModelVia(dM.Map, F), (dM.InDomain∘F), Domain, (dM.xyp[1], dM.xyp[2], length(Domain)), CreateSymbolNames(length(Domain), "θ"), dM.StaticOutput, dM.inplace, dM.CustomEmbedding)
end

"""
    Embedding(DM::AbstractDataModel, F::Function, start::Vector; Domain::HyperCube=FullDomain(length(start))) -> DataModel
Transforms a model function via `newmodel(x, θ) = oldmodel(x, F(θ))` and returns the associated `DataModel`.
An initial parameter configuration `start` as well as a `Domain` can optionally be passed to the `DataModel` constructor.
"""
function Embedding(DM::AbstractDataModel, F::Function, start::AbstractVector{<:Number}=GetStartP(GetArgLength(F)); Domain::HyperCube=FullDomain(length(start)))
    DataModel(Data(DM), EmbedModelVia(Predictor(DM), F; Domain=Domain), EmbedDModelVia(dPredictor(DM), F; Domain=Domain), start)
end


LinearModel(x::Union{Number,AbstractVector{<:Number}}, θ::AbstractVector{<:Number}) = dot(θ[1:end-1], x) + θ[end]
QuadraticModel(x::Union{Number,AbstractVector{<:Number}}, θ::AbstractVector{<:Number}) = dot(θ[1:Int((end-1)/2)], x.^2) + dot(θ[Int((end-1)/2)+1:end-1], x) + θ[end]
ExponentialModel(x::Union{Number,AbstractVector{<:Number}}, θ::AbstractVector{<:Number}) = exp(LinearModel(x,θ))
SumExponentialsModel(x::Union{Number,AbstractVector{<:Number}}, θ::AbstractVector{<:Number}) = sum(exp.(θ .* x))

function PolynomialModel(degree::Int)
    Polynomial(x::Number, θ::AbstractVector{<:Number}) = sum(θ[i] * x^(i-1) for i in 1:(degree+1))
end
