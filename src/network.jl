# currency metabolites: cofactors in hundreds of reactions, so routing through them
# links everything to everything (h+ -> succinate)
# matched on the id without its compartment (atp_c -> atp) and on the lowercase name
const DEFAULT_CURRENCY = Set([
    "h", "h2o", "atp", "adp", "amp", "gtp", "gdp", "gmp", "utp", "udp", "ump", "ctp", "cdp", "cmp",
    "itp", "idp", "nad", "nadh", "nadp", "nadph", "fad", "fadh2", "fmn", "fmnh2", "pi", "ppi",
    "co2", "o2", "nh4", "nh3", "coa", "q8", "q8h2", "mqn8", "mql8", "2dmmq8", "2dmmql8", "h2o2",
    "so4", "hco3", "na1", "k", "cl", "fe2", "fe3", "o2s", "trdox", "trdrd", "gthox", "gthrd",
    # names, for models without bigg ids (human-gem)
    "h+", "proton", "water", "atp", "adp", "amp", "nad+", "nadh", "nadp+", "nadph", "phosphate",
    "diphosphate", "pyrophosphate", "co2", "carbon dioxide", "o2", "oxygen", "ammonium", "nh3",
    "coenzyme a", "coa", "fad", "fadh2", "ubiquinone", "ubiquinol",
])

base_id(id::AbstractString) = replace(id, r"_[A-Za-z0-9]{1,3}$" => "")

function is_currency(model::Model, id::AbstractString, currency)
    base_id(id) in currency && return true
    metabolite = get(model.metabolites, id, nothing)
    return metabolite !== nothing && lowercase(metabolite.name) in currency
end

# comma- or space-separated list from the api
parse_currency(text::AbstractString) =
    Set(lowercase(strip(item)) for item in split(text, r"[,\s]+") if !isempty(strip(item)))

# reactions that can make or use the metabolite under their bounds
# reversible reactions land in both lists; after fba each entry carries its rate (flux × coefficient)
function metabolite_analysis(model::Model, metabolite_id::AbstractString)
    get_metabolite(model, metabolite_id)
    producers, consumers = NamedTuple[], NamedTuple[]
    for index in get(model.metabolite_reactions, metabolite_id, Int[])
        reaction = model.reactions[index]
        coefficient = reaction.stoichiometry[metabolite_id]
        flux = get(model.fluxes, reaction.id, nothing)
        item = (id=reaction.id, name=reaction.name, equation=reaction_equation(model, reaction),
                coefficient=coefficient, flux=flux, rate=flux === nothing ? nothing : flux * coefficient,
                reversible=can_run_forward(reaction) && can_run_backward(reaction))
        produces = (coefficient > 0 && can_run_forward(reaction)) || (coefficient < 0 && can_run_backward(reaction))
        consumes = (coefficient < 0 && can_run_forward(reaction)) || (coefficient > 0 && can_run_backward(reaction))
        produces && push!(producers, item)
        consumes && push!(consumers, item)
    end
    by_activity(item) = (item.rate === nothing ? 0.0 : -abs(item.rate), item.id)
    sort!(producers; by=by_activity)
    sort!(consumers; by=by_activity)
    total(items, sign) = isempty(model.fluxes) ? nothing : sum((max(sign * something(item.rate, 0.0), 0.0) for item in items); init=0.0)
    return (producers=producers, consumers=consumers,
            produced_flux=total(producers, 1), consumed_flux=total(consumers, -1))
end

const FLUX_TOLERANCE = 1e-9

# drawn direction: fba flux sign first, else the bounds (:forward, :backward, :reversible, :blocked)
# second value: true when an active flux decided it
function drawn_direction(model::Model, reaction::Reaction)
    flux = get(model.fluxes, reaction.id, nothing)
    if flux !== nothing
        flux > FLUX_TOLERANCE && return :forward, true
        flux < -FLUX_TOLERANCE && return :backward, true
    end
    forward, backward = can_run_forward(reaction), can_run_backward(reaction)
    forward && backward && return :reversible, false
    forward && return :forward, false
    backward && return :backward, false
    return :blocked, false
end

# bipartite graph for the ui: metabolite and reaction nodes
# edges run substrate -> reaction -> product in the drawn direction
mutable struct NetworkBuilder
    model::Model
    nodes::Vector{Dict{Symbol, Any}}
    node_index::Dict{String, Int}
    edges::Vector{Dict{Symbol, Any}}
end

NetworkBuilder(model::Model) = NetworkBuilder(model, Dict{Symbol, Any}[], Dict{String, Int}(), Dict{Symbol, Any}[])

function add_metabolite_node!(builder::NetworkBuilder, id::AbstractString; role="metabolite")
    key = "met:" * id
    haskey(builder.node_index, key) && return key
    metabolite = builder.model.metabolites[id]
    push!(builder.nodes, Dict{Symbol, Any}(:key => key, :id => id, :kind => "metabolite", :label => id,
                                          :name => metabolite.name, :role => role))
    builder.node_index[key] = length(builder.nodes)
    return key
end

function add_reaction_node!(builder::NetworkBuilder, reaction::Reaction; hidden_metabolites=0, key="rxn:" * reaction.id)
    haskey(builder.node_index, key) && return key
    direction, active = drawn_direction(builder.model, reaction)
    push!(builder.nodes, Dict{Symbol, Any}(:key => key, :id => reaction.id, :kind => "reaction", :label => reaction.id,
                                          :name => reaction.name, :role => "reaction",
                                          :flux => get(builder.model.fluxes, reaction.id, nothing),
                                          :direction => String(direction), :active => active,
                                          :hidden_metabolites => hidden_metabolites))
    builder.node_index[key] = length(builder.nodes)
    return key
end

# edge between a metabolite and a reaction node
# oriented by the drawn direction, or by outgoing (reaction -> metabolite) when the caller knows it
function connect!(builder::NetworkBuilder, reaction::Reaction, metabolite_id::AbstractString; outgoing=nothing,
                  reaction_key="rxn:" * reaction.id)
    metabolite_key = "met:" * metabolite_id
    direction, active = drawn_direction(builder.model, reaction)
    if outgoing === nothing
        is_product = reaction.stoichiometry[metabolite_id] > 0
        outgoing = direction === :backward ? !is_product : is_product
    else
        direction = :forward  # orientation known: not drawn as reversible
    end
    source, target = outgoing ? (reaction_key, metabolite_key) : (metabolite_key, reaction_key)
    any(edge -> edge[:source] == source && edge[:target] == target, builder.edges) && return
    push!(builder.edges, Dict{Symbol, Any}(:source => source, :target => target, :active => active,
                                          :reversible => direction === :reversible))
end

# x, y in [0, 1] for every node (stress majorization)
function layout!(builder::NetworkBuilder; fixed=Dict{String, Tuple{Float64, Float64}}())
    count = length(builder.nodes)
    count == 0 && return builder
    if count == 1
        builder.nodes[1][:x], builder.nodes[1][:y] = 0.5, 0.5
        return builder
    end
    graph = SimpleGraph(count)
    for edge in builder.edges
        add_edge!(graph, builder.node_index[edge[:source]], builder.node_index[edge[:target]])
    end
    pin = Dict{Int, NTuple{2, Bool}}()
    initial = Dict{Int, Point2{Float64}}()
    for (key, (x, y)) in fixed
        index = builder.node_index[key]
        initial[index] = Point2(x, y)
        pin[index] = (true, true)
    end
    positions = NetworkLayout.stress(graph; seed=1, initialpos=initial, pin=pin)
    xs, ys = first.(positions), last.(positions)
    span = max(maximum(xs) - minimum(xs), maximum(ys) - minimum(ys), 1e-9)
    for (node, x, y) in zip(builder.nodes, xs, ys)
        node[:x] = (x - minimum(xs)) / span
        node[:y] = (y - minimum(ys)) / span
    end
    return builder
end

network_payload(builder::NetworkBuilder) = (nodes=builder.nodes, edges=builder.edges)

# one-reaction neighbourhood of a metabolite
# at most max_reactions (largest |flux| first), currency hidden,
# reactions with more than max_partners partners (biomass) drawn without them
function local_network(model::Model, metabolite_id::AbstractString; max_reactions::Integer=25,
                       hide_currency::Bool=true, currency=DEFAULT_CURRENCY, max_partners::Integer=8)
    get_metabolite(model, metabolite_id)
    indices = copy(get(model.metabolite_reactions, metabolite_id, Int[]))
    sort!(indices; by=i -> (-abs(get(model.fluxes, model.reactions[i].id, 0.0)), model.reactions[i].id))
    shown = indices[1:min(max_reactions, length(indices))]

    builder = NetworkBuilder(model)
    center = add_metabolite_node!(builder, metabolite_id; role="selected")
    for index in shown
        reaction = model.reactions[index]
        partners = [id for id in keys(reaction.stoichiometry)
                    if id != metabolite_id && !(hide_currency && is_currency(model, id, currency))]
        sort!(partners)
        hidden = length(partners) > max_partners ? length(partners) : 0
        add_reaction_node!(builder, reaction; hidden_metabolites=hidden)
        connect!(builder, reaction, metabolite_id)
        hidden > 0 && continue
        for id in partners
            add_metabolite_node!(builder, id)
            connect!(builder, reaction, id)
        end
    end
    layout!(builder; fixed=Dict(center => (0.0, 0.0)))
    return (network_payload(builder)..., total_reactions=length(indices), shown_reactions=length(shown))
end
