# sparse S: metabolites x reactions
function stoichiometric_matrix(model::Model, metabolite_ids::Vector{String})
    row = Dict(id => i for (i, id) in enumerate(metabolite_ids))
    I, J, V = Int[], Int[], Float64[]
    for (j, reaction) in enumerate(model.reactions), (id, coefficient) in reaction.stoichiometry
        push!(I, row[id]); push!(J, j); push!(V, coefficient)
    end
    return sparse(I, J, V, length(metabolite_ids), length(model.reactions))
end

# fba: optimize v[objective] subject to S v = 0 and lb ≤ v ≤ ub (lp, highs)
# fluxes stay on the model so every view can show them
function run_fba!(model::Model, objective_id::AbstractString; sense::Symbol=:max)
    sense in (:max, :min) || throw(ArgumentError("sense must be :max or :min"))
    objective_index = get(model.reaction_index, objective_id, nothing)
    objective_index === nothing && throw(ArgumentError("no reaction $objective_id"))
    for reaction in model.reactions
        reaction.lower_bound <= reaction.upper_bound ||
            throw(ArgumentError("$(reaction.id): lower bound $(reaction.lower_bound) above upper bound $(reaction.upper_bound)"))
    end

    S = stoichiometric_matrix(model, sort!(collect(keys(model.metabolites))))
    n = length(model.reactions)
    lower = [reaction.lower_bound for reaction in model.reactions]
    upper = [reaction.upper_bound for reaction in model.reactions]

    lp = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(lp)
    JuMP.@variable(lp, lower[j] <= v[j=1:n] <= upper[j])
    JuMP.@constraint(lp, S * v .== 0)
    JuMP.@objective(lp, sense === :max ? JuMP.MAX_SENSE : JuMP.MIN_SENSE, v[objective_index])
    JuMP.optimize!(lp)

    status = string(JuMP.termination_status(lp))
    model.objective_reaction = String(objective_id)
    model.objective_sense = sense
    model.fba_status = status
    if JuMP.termination_status(lp) == JuMP.OPTIMAL && JuMP.has_values(lp)
        # values under 1e-9 are solver noise; report them as 0
        values = JuMP.value.(v)
        model.fluxes = Dict(reaction.id => (abs(x) < FLUX_TOLERANCE ? 0.0 : x) for (reaction, x) in zip(model.reactions, values))
        model.objective_value = JuMP.objective_value(lp)
    else
        # infeasible or unbounded: no fluxes to show
        model.fluxes = Dict{String, Float64}()
        model.objective_value = nothing
    end
    return fba_result(model)
end

fba_result(model::Model) = (status=model.fba_status, objective_reaction=model.objective_reaction,
                            sense=String(model.objective_sense), objective_value=model.objective_value,
                            fluxes=copy(model.fluxes))
