# gem-stone: analyse genome-scale metabolic models from a local browser gui
# julia does the analysis; the react native ui in public/ only renders it
module GEMStone

import AbstractFBCModels as A
import SBMLFBCModels, JSONFBCModels, MATFBCModels  # registers each format with A.load
using Graphs
using HiGHS
using HTTP
using JSON3
using JuMP: JuMP
using NetworkLayout
using NetworkLayout: Point2
using SparseArrays
using URIs

export Model, Reaction, Metabolite, load_model, reaction_equation, reaction_details, search_reactions,
       metabolite_analysis, local_network, pathway_routes, default_sources, run_fba!,
       DEFAULT_CURRENCY

include("model.jl")
include("search.jl")
include("network.jl")
include("pathway.jl")
include("fba.jl")
include("server.jl")

end
