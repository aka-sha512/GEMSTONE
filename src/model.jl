struct Metabolite
    id::String
    name::String
    compartment::String
    formula::String
    carbons::Int  # carbon atoms in the formula; -1 if unknown
end

struct Reaction
    id::String
    name::String
    stoichiometry::Dict{String, Float64}
    lower_bound::Float64
    upper_bound::Float64
    genes::Vector{String}
    gpr::String
end

mutable struct Model
    id::String
    name::String
    format::String
    metabolites::Dict{String, Metabolite}
    reactions::Vector{Reaction}
    reaction_index::Dict{String, Int}
    metabolite_reactions::Dict{String, Vector{Int}}
    gene_names::Dict{String, String}
    objective_reaction::String
    objective_sense::Symbol
    fluxes::Dict{String, Float64}
    objective_value::Union{Nothing, Float64}
    fba_status::String
end

const SUPPORTED_EXTENSIONS = (".xml", ".sbml", ".json", ".mat")

# bigg sbml prefixes ids with R_, M_ and G_; strip only when every id has it

function _prefix_stripper(ids, prefix)
    all(id -> startswith(id, prefix) && length(id) > length(prefix), ids) || return identity
    return id -> id[(length(prefix) + 1):end]
end

_text(value, default="") = value === nothing ? default : string(value)

function _formula(dict)
    dict === nothing && return ""
    isempty(dict) && return ""
    order = sort!(collect(keys(dict)); by=element -> (element == "C" ? 0 : element == "H" ? 1 : 2, element))
    return join(element * (dict[element] == 1 ? "" : string(dict[element])) for element in order)
end

# model id and name, wherever the format keeps them
function _model_title(raw, fallback)
    for getter in (m -> (m.sbml.id, m.sbml.name), m -> (m.json["id"], get(m.json, "name", nothing)), m -> (m.id, nothing))
        try
            id, name = getter(raw)
            id = _text(id, "")
            isempty(id) && continue
            return id, _text(name, id)
        catch
        end
    end
    return fallback, fallback
end

# mat files may lack compartments: take the id suffix (pyr_c -> c)
_compartment_from_id(id) = (m = match(r"_([A-Za-z0-9]{1,3})$", id); m === nothing ? "" : m.captures[1])

# gene rule as text: (a and b) or c
function _gpr_string(dnf, rename, gene_names)
    dnf === nothing && return ""
    isempty(dnf) && return ""
    clause(genes) = length(genes) == 1 ? rename(only(genes)) : "(" * join(rename.(genes), " and ") * ")"
    return join((clause(genes) for genes in dnf), " or ")
end

# read an sbml, cobra json or cobra mat model
function load_model(path::AbstractString; name=nothing)
    extension = lowercase(splitext(path)[2])
    extension in SUPPORTED_EXTENSIONS ||
        throw(ArgumentError("unsupported file type '$extension'; use $(join(SUPPORTED_EXTENSIONS, ", "))"))
    raw = try
        A.load(path)
    catch exception
        throw(ArgumentError("cannot read $(basename(path)) as a model: $(sprint(showerror, exception))"))
    end
    stem = name === nothing ? splitext(basename(path))[1] : String(name)

    reaction_ids = A.reactions(raw)
    metabolite_ids = A.metabolites(raw)
    gene_ids = A.genes(raw)
    isempty(reaction_ids) && throw(ArgumentError("no reactions in $(basename(path))"))
    isempty(metabolite_ids) && throw(ArgumentError("no metabolites in $(basename(path))"))

    rxn = _prefix_stripper(reaction_ids, "R_")
    met = _prefix_stripper(metabolite_ids, "M_")
    gene = _prefix_stripper(gene_ids, "G_")

    metabolites = Dict{String, Metabolite}()
    for id in metabolite_ids
        new_id = met(id)
        compartment = _text(A.metabolite_compartment(raw, id))
        isempty(compartment) && (compartment = _compartment_from_id(new_id))
        formula = A.metabolite_formula(raw, id)
        carbons = formula === nothing || isempty(formula) ? -1 : Int(get(formula, "C", 0))
        metabolites[new_id] = Metabolite(new_id, _text(A.metabolite_name(raw, id), new_id), compartment,
                                         _formula(formula), carbons)
    end

    gene_names = Dict{String, String}()
    for id in gene_ids
        gene_names[gene(id)] = _text(A.gene_name(raw, id), "")
    end

    lower, upper = A.bounds(raw)
    reactions = Reaction[]
    for (index, id) in enumerate(reaction_ids)
        stoichiometry = Dict{String, Float64}(met(m) => Float64(c) for (m, c) in A.reaction_stoichiometry(raw, id) if c != 0)
        dnf = A.reaction_gene_association_dnf(raw, id)
        genes = dnf === nothing ? String[] : sort!(unique(gene(g) for clause in dnf for g in clause))
        lb, ub = Float64(lower[index]), Float64(upper[index])
        push!(reactions, Reaction(rxn(id), _text(A.reaction_name(raw, id), rxn(id)), stoichiometry,
                                  lb, ub, genes, _gpr_string(dnf, gene, gene_names)))
    end

    objective = A.objective(raw)
    objective_index = findfirst(!iszero, objective)
    # no objective in the file: first reaction named biomass, else the first reaction
    if objective_index === nothing
        objective_index = something(findfirst(r -> occursin("biomass", lowercase(r.id)), reactions), 1)
    end
    objective_sense = objective_index !== nothing && objective[objective_index] < 0 ? :min : :max

    model_id, model_name = _model_title(raw, stem)
    format = extension == ".json" ? "COBRA JSON" : extension == ".mat" ? "COBRA MAT" : "SBML"
    model = Model(model_id, model_name, format, metabolites, reactions, Dict{String, Int}(),
                  Dict{String, Vector{Int}}(), gene_names, reactions[objective_index].id, objective_sense,
                  Dict{String, Float64}(), nothing, "not run")
    reindex!(model)
    return model
end

# lookups: reaction id -> position, metabolite -> its reactions
function reindex!(model::Model)
    model.reaction_index = Dict(reaction.id => index for (index, reaction) in enumerate(model.reactions))
    model.metabolite_reactions = Dict(id => Int[] for id in keys(model.metabolites))
    for (index, reaction) in enumerate(model.reactions), id in keys(reaction.stoichiometry)
        push!(get!(model.metabolite_reactions, id, Int[]), index)
    end
    return model
end

function get_reaction(model::Model, id::AbstractString)
    index = get(model.reaction_index, id, nothing)
    index === nothing && throw(ArgumentError("no reaction $id"))
    return model.reactions[index]
end

function get_metabolite(model::Model, id::AbstractString)
    haskey(model.metabolites, id) || throw(ArgumentError("no metabolite $id"))
    return model.metabolites[id]
end

gene_count(model::Model) = length(model.gene_names)

# boundary reaction (exchange, demand, sink): metabolites on one side only
function is_boundary(reaction::Reaction)
    isempty(reaction.stoichiometry) && return false
    coefficients = values(reaction.stoichiometry)
    return all(<(0), coefficients) || all(>(0), coefficients)
end

# what a boundary reaction can feed into the network under its bounds
function uptake_metabolites(reaction::Reaction)
    is_boundary(reaction) || return String[]
    consumes = all(<(0), values(reaction.stoichiometry))
    can_supply = consumes ? reaction.lower_bound < 0 : reaction.upper_bound > 0
    return can_supply ? collect(keys(reaction.stoichiometry)) : String[]
end

can_run_forward(reaction::Reaction) = reaction.upper_bound > 0
can_run_backward(reaction::Reaction) = reaction.lower_bound < 0

_number_text(x) = isinteger(x) && abs(x) < 1e15 ? string(Int(x)) : string(round(x; sigdigits=6))

# arrow from the bounds: <=> both ways, --> forward, <-- backward, -x- blocked
function _arrow(reaction::Reaction)
    forward, backward = can_run_forward(reaction), can_run_backward(reaction)
    forward && backward && return "<=>"
    backward && return "<--"
    forward && return "-->"
    return "-x-"
end

# equation with metabolite ids (labels=:id) or names (labels=:name)
function reaction_equation(model::Model, reaction::Reaction; labels::Symbol=:id)
    function side(predicate)
        terms = String[]
        for (id, coefficient) in sort!(collect(reaction.stoichiometry); by=first)
            predicate(coefficient) || continue
            label = labels === :name ? get(model.metabolites, id, Metabolite(id, id, "", "", -1)).name : id
            amount = abs(coefficient)
            push!(terms, (amount == 1 ? "" : _number_text(amount) * " ") * label)
        end
        return isempty(terms) ? "∅" : join(terms, " + ")
    end
    return string(side(<(0)), " ", _arrow(reaction), " ", side(>(0)))
end

# everything the reactions view shows
function reaction_details(model::Model, id::AbstractString)
    reaction = get_reaction(model, id)
    return (
        id=reaction.id,
        name=reaction.name,
        equation=reaction_equation(model, reaction),
        equation_names=reaction_equation(model, reaction; labels=:name),
        lower_bound=reaction.lower_bound,
        upper_bound=reaction.upper_bound,
        reversible=can_run_forward(reaction) && can_run_backward(reaction),
        boundary=is_boundary(reaction),
        gpr=reaction.gpr,
        genes=[(id=gene, name=get(model.gene_names, gene, "")) for gene in reaction.genes],
        metabolites=[(id=id, name=get(model.metabolites, id, Metabolite(id, id, "", "", -1)).name, coefficient=c)
                     for (id, c) in sort!(collect(reaction.stoichiometry); by=item -> (item[2] > 0, item[1]))],
        flux=get(model.fluxes, reaction.id, nothing),
        is_objective=reaction.id == model.objective_reaction,
    )
end

# header counts plus the id lists for the inputs
function model_summary(model::Model)
    by_name(items) = sort!(items; by=item -> (lowercase(item.name), item.id))
    return (
        id=model.id,
        name=model.name,
        format=model.format,
        metabolite_count=length(model.metabolites),
        reaction_count=length(model.reactions),
        gene_count=gene_count(model),
        objective_reaction=model.objective_reaction,
        objective_sense=String(model.objective_sense),
        objective_value=model.objective_value,
        fba_status=model.fba_status,
        metabolites=by_name([(id=m.id, name=m.name, compartment=m.compartment) for m in values(model.metabolites)]),
        reactions=[(id=r.id, name=r.name) for r in model.reactions],
        default_sources=default_sources(model, DEFAULT_CURRENCY),
        default_currency=sort!(collect(DEFAULT_CURRENCY)),
    )
end
