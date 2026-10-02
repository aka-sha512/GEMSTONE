const SEARCH_FIELDS = ("all", "id", "name", "metabolite", "gene")

_contains(text, needle) = occursin(needle, lowercase(text))

function _match_rank(model::Model, reaction::Reaction, needle::AbstractString, field::AbstractString)
    id = lowercase(reaction.id)
    if field in ("all", "id")
        id == needle && return 0
        startswith(id, needle) && return 1
        occursin(needle, id) && return 2
    end
    if field in ("all", "name")
        _contains(reaction.name, needle) && return 3
    end
    if field in ("all", "metabolite")
        for metabolite_id in keys(reaction.stoichiometry)
            lowercase(metabolite_id) == needle && return 4
        end
        for metabolite_id in keys(reaction.stoichiometry)
            metabolite = get(model.metabolites, metabolite_id, nothing)
            (_contains(metabolite_id, needle) || (metabolite !== nothing && _contains(metabolite.name, needle))) && return 5
        end
    end
    if field in ("all", "gene")
        for gene in reaction.genes
            (lowercase(gene) == needle || lowercase(get(model.gene_names, gene, "")) == needle) && return 6
        end
        for gene in reaction.genes
            (_contains(gene, needle) || _contains(get(model.gene_names, gene, ""), needle)) && return 7
        end
    end
    return nothing
end



function search_reactions(model::Model, query::AbstractString; field::AbstractString="all")
    field in SEARCH_FIELDS || error("Unknown search field '$field'.")
    needle = lowercase(strip(query))
    isempty(needle) && return copy(model.reactions)
    ranked = Tuple{Int, String, Reaction}[]
    for reaction in model.reactions
        rank = _match_rank(model, reaction, needle, field)
        rank === nothing || push!(ranked, (rank, reaction.id, reaction))
    end
    sort!(ranked; by=item -> (item[1], item[2]))
    return [item[3] for item in ranked]
end
