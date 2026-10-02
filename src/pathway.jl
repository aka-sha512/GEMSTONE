# the medium: what boundary reactions can supply, minus currency
# default start points for routes
function default_sources(model::Model, currency)
    sources = Set{String}()
    for reaction in model.reactions, id in uptake_metabolites(reaction)
        is_currency(model, id, currency) || push!(sources, id)
    end
    return sort!(collect(sources))
end

const LUMPED_REACTION_SIZE = 12   # more non-currency metabolites than this: lumped (biomass)

_carbon_similarity(a, b) = a <= 0 || b <= 0 ? 0.0 : min(a, b) / max(a, b)

# substrate -> product pairs that likely share a carbon skeleton
# no atom mappings, so each substrate pairs with the product(s) closest in carbon count:
# pyr + glu -> ala + akg keeps pyr -> ala and glu -> akg, drops pyr -> akg
# unknown formulas or no carbon: every pair
function reactant_pairs(model::Model, inputs, outputs)
    pairs = Set{Tuple{String, String}}()
    (isempty(inputs) || isempty(outputs)) && return pairs
    carbons(id) = model.metabolites[id].carbons
    if any(id -> carbons(id) < 0, inputs) || any(id -> carbons(id) < 0, outputs) ||
       all(id -> carbons(id) == 0, inputs) || all(id -> carbons(id) == 0, outputs)
        return Set((u, v) for u in inputs, v in outputs)
    end
    for u in inputs
        scores = [_carbon_similarity(carbons(u), carbons(v)) for v in outputs]
        best = maximum(scores)
        best > 0 || continue
        for (v, score) in zip(outputs, scores)
            score == best && push!(pairs, (u, v))
        end
    end
    return pairs
end

# directed metabolite graph for routes: u -> v when a non-boundary reaction turns u into v
# direction from the bounds, or from the fba flux with flux_only; u, v carbon-matched; no currency
# lumped reactions only with allow_lumped, and only as the last step into target
function metabolite_graph(model::Model, target::AbstractString; currency=DEFAULT_CURRENCY, flux_only::Bool=false,
                          allow_lumped::Bool=false)
    ids = sort!(collect(keys(model.metabolites)))
    index = Dict(id => i for (i, id) in enumerate(ids))
    graph = SimpleDiGraph(length(ids))
    edge_reactions = Dict{Tuple{Int, Int}, Vector{String}}()
    keep(id) = id == target || !is_currency(model, id, currency)

    for reaction in model.reactions
        is_boundary(reaction) && continue
        directions = Symbol[]
        if flux_only
            flux = get(model.fluxes, reaction.id, 0.0)
            flux > FLUX_TOLERANCE && push!(directions, :forward)
            flux < -FLUX_TOLERANCE && push!(directions, :backward)
        else
            can_run_forward(reaction) && push!(directions, :forward)
            can_run_backward(reaction) && push!(directions, :backward)
        end
        substrates = [id for (id, c) in reaction.stoichiometry if c < 0 && keep(id)]
        products = [id for (id, c) in reaction.stoichiometry if c > 0 && keep(id)]
        lumped = length(substrates) + length(products) > LUMPED_REACTION_SIZE
        lumped && !allow_lumped && continue
        for direction in directions
            inputs, outputs = direction === :forward ? (substrates, products) : (products, substrates)
            pairs = lumped ? Set((u, target) for u in inputs if target in outputs) : reactant_pairs(model, inputs, outputs)
            for (u, v) in pairs
                u == v && continue
                add_edge!(graph, index[u], index[v])
                push!(get!(edge_reactions, (index[u], index[v]), String[]), reaction.id)
            end
        end
    end
    return (graph=graph, ids=ids, index=index, edge_reactions=edge_reactions)
end

# several reactions for one step: the one with the most flux
function _pick_reaction(model::Model, candidates::Vector{String})
    isempty(model.fluxes) && return first(candidates)
    return candidates[argmax([abs(get(model.fluxes, id, 0.0)) for id in candidates])]
end

# shortest routes (fewest reactions, yen's k-shortest paths) from each source to target
# returns the routes and their union as a drawable network
function pathway_routes(model::Model, target::AbstractString; sources=nothing, per_source::Integer=3,
                        limit::Integer=8, max_steps::Integer=20, currency=DEFAULT_CURRENCY, flux_only::Bool=false)
    get_metabolite(model, target)
    flux_only && isempty(model.fluxes) && throw(ArgumentError("run fba first"))
    sources = sources === nothing || isempty(sources) ? default_sources(model, currency) : collect(sources)
    for source in sources
        get_metabolite(model, source)
    end

    # lumped reactions (biomass) only if nothing else connects;
    # otherwise they shortcut: glucose -> biomass -> 2-oxoglutarate
    routes = _find_routes(model, target, sources, per_source, max_steps, currency, flux_only, false)
    isempty(routes) && (routes = _find_routes(model, target, sources, per_source, max_steps, currency, flux_only, true))
    sort!(routes; by=route -> (route.steps, route.source, route.reactions))
    routes = routes[1:min(limit, length(routes))]

    detailed = [(
        source=route.source,
        source_name=model.metabolites[route.source].name,
        steps=route.steps,
        metabolites=[(id=id, name=model.metabolites[id].name) for id in route.metabolites],
        reactions=[(id=id, name=get_reaction(model, id).name, equation=reaction_equation(model, get_reaction(model, id)),
                    flux=get(model.fluxes, id, nothing)) for id in route.reactions],
    ) for route in routes]
    return (routes=detailed, network=_route_network(model, routes, target), sources=sources)
end

# k routes per source on one graph
function _find_routes(model, target, sources, per_source, max_steps, currency, flux_only, allow_lumped)
    net = metabolite_graph(model, target; currency=currency, flux_only=flux_only, allow_lumped=allow_lumped)
    distances = weights(net.graph)
    routes = NamedTuple[]
    for source in sources
        source == target && continue
        state = yen_k_shortest_paths(net.graph, net.index[source], net.index[target], distances, per_source;
                                     maxdist=max_steps)
        for path in state.paths
            metabolites = net.ids[path]
            reactions = [_pick_reaction(model, net.edge_reactions[(path[i], path[i + 1])]) for i in 1:(length(path) - 1)]
            push!(routes, (source=source, metabolites=metabolites, reactions=reactions, steps=length(reactions)))
        end
    end
    return routes
end

# union of routes, top to bottom by step: sources at the top, target at the bottom
# one reaction node per pair, so the pts (glc + pep -> g6p + pyr) shows up at both places it is used
function _route_network(model::Model, routes, target)
    builder = NetworkBuilder(model)
    level = Dict{String, Int}()
    place!(key, value) = (level[key] = min(get(level, key, typemax(Int)), value))
    for route in routes
        for (step, id) in enumerate(route.metabolites)
            role = id == target ? "target" : step == 1 ? "source" : "metabolite"
            place!(add_metabolite_node!(builder, id; role=role), 2 * (step - 1))
        end
        for (step, reaction_id) in enumerate(route.reactions)
            reaction = get_reaction(model, reaction_id)
            from, to = route.metabolites[step], route.metabolites[step + 1]
            key = "rxn:$(reaction.id):$from>$to"
            add_reaction_node!(builder, reaction; key=key)
            place!(key, 2 * step - 1)
            connect!(builder, reaction, from; outgoing=false, reaction_key=key)
            connect!(builder, reaction, to; outgoing=true, reaction_key=key)
        end
    end
    isempty(builder.nodes) && return network_payload(builder)
    target_key = "met:" * target
    haskey(level, target_key) && (level[target_key] = maximum(values(level)))
    levels = maximum(values(level))
    by_level = Dict{Int, Vector{Dict{Symbol, Any}}}()
    for node in builder.nodes
        push!(get!(by_level, level[node[:key]], Dict{Symbol, Any}[]), node)
    end
    for (l, nodes) in by_level, (column, node) in enumerate(nodes)
        node[:x] = length(nodes) == 1 ? 0.5 : (column - 1) / (length(nodes) - 1)
        node[:y] = levels == 0 ? 0.5 : l / levels
    end
    return (network_payload(builder)..., levels=levels + 1,
            width=maximum(length(nodes) for nodes in values(by_level)))
end
