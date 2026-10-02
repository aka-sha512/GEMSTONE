const EXAMPLES_DIR = normpath(joinpath(@__DIR__, "..", "examples"))
# built ui (pnpm build in web/ writes here)
const PUBLIC_DIR = normpath(joinpath(@__DIR__, "..", "public"))
const MIME_TYPES = Dict(".html" => "text/html; charset=utf-8", ".js" => "text/javascript; charset=utf-8",
                        ".css" => "text/css; charset=utf-8", ".json" => "application/json", ".svg" => "image/svg+xml",
                        ".png" => "image/png", ".ico" => "image/x-icon", ".woff2" => "font/woff2", ".map" => "application/json")
const DEFAULT_EXAMPLE = "e_coli_core.json"
const MAX_SEARCH_RESULTS = 250
const MAX_UPLOAD_BYTES = 1024^3  # human gems outgrow http.jl's 64 mib default

# one active model per server process
const STATE = Ref{Union{Nothing, Model}}(nothing)
const STATE_LOCK = ReentrantLock()

current_model() = something(STATE[], nothing) === nothing ? throw(ArgumentError("no model loaded")) : STATE[]

list_examples() = sort!([file for file in readdir(EXAMPLES_DIR) if lowercase(splitext(file)[2]) in SUPPORTED_EXTENSIONS])

function load_example(name::AbstractString)
    name in list_examples() || throw(ArgumentError("no example $name"))
    return load_model(joinpath(EXAMPLES_DIR, name))
end

json_response(payload; status=200) =
    HTTP.Response(status, ["Content-Type" => "application/json; charset=utf-8"], JSON3.write(payload))

# request helpers
_query(request) = URIs.queryparams(URIs.URI(String(request.target)))
_body(request)::Vector{UInt8} = request.body isa AbstractString ? Vector{UInt8}(codeunits(request.body)) : Vector{UInt8}(request.body)
_json_body(request) = JSON3.read(String(_body(request)))
_flag(params, key, default) = haskey(params, key) ? lowercase(params[key]) in ("1", "true", "yes", "on") : default
_int(params, key, default) = haskey(params, key) ? parse(Int, params[key]) : default

function _currency(params)
    text = get(params, "currency", nothing)
    return text === nothing ? DEFAULT_CURRENCY : parse_currency(text)
end

_summary(model) = (model_summary(model)..., examples=list_examples())

function _replace_model!(model)
    STATE[] = model
    return json_response(_summary(model))
end

# api paths under /api/, anything else is a file from public/
function route(request::HTTP.Request)
    uri = URIs.URI(String(request.target))
    path, method = uri.path, request.method
    if method in ("GET", "HEAD") && !startswith(path, "/api/")
        return static_file(path)
    end
    path == "/api/examples" && return json_response(list_examples())
    if method == "POST" && path == "/api/upload"
        filename = basename(get(_query(request), "filename", ""))
        extension = lowercase(splitext(filename)[2])
        extension in SUPPORTED_EXTENSIONS ||
            throw(ArgumentError("upload a model file: $(join(SUPPORTED_EXTENSIONS, ", "))"))
        # load from a temporary copy; it is deleted afterwards
        model = mktempdir() do dir
            file = joinpath(dir, filename)
            write(file, _body(request))
            load_model(file)
        end
        return _replace_model!(model)
    elseif method == "POST" && path == "/api/example"
        return _replace_model!(load_example(get(_query(request), "name", DEFAULT_EXAMPLE)))
    end

    model = current_model()
    params = _query(request)
    if method == "GET" && path == "/api/model"
        return json_response(_summary(model))
    elseif method == "GET" && path == "/api/search"
        matches = search_reactions(model, get(params, "q", ""); field=get(params, "field", "all"))
        shown = matches[1:min(MAX_SEARCH_RESULTS, length(matches))]
        return json_response((total=length(matches), results=[(id=r.id, name=r.name, flux=get(model.fluxes, r.id, nothing)) for r in shown]))
    elseif method == "GET" && path == "/api/reaction"
        return json_response(reaction_details(model, get(params, "id", "")))
    elseif method == "GET" && path == "/api/metabolite"
        id = get(params, "id", "")
        metabolite = get_metabolite(model, id)
        network = local_network(model, id; max_reactions=_int(params, "max", 25),
                                hide_currency=_flag(params, "hide_currency", true), currency=_currency(params))
        return json_response((metabolite=metabolite, is_currency=is_currency(model, id, _currency(params)),
                              metabolite_analysis(model, id)..., network=network))
    elseif method == "GET" && path == "/api/pathways"
        sources = filter(!isempty, strip.(split(get(params, "sources", ""), ",")))
        result = pathway_routes(model, get(params, "target", ""); sources=sources,
                                per_source=_int(params, "k", 3), limit=_int(params, "limit", 8),
                                max_steps=_int(params, "max_steps", 20), currency=_currency(params),
                                flux_only=_flag(params, "flux_only", false))
        return json_response(result)
    elseif method == "POST" && path == "/api/fba"
        body = _json_body(request)
        sense = Symbol(String(get(body, :sense, "max")))
        return json_response(run_fba!(model, String(body.objective); sense=sense))
    end
    return json_response((error="not found: $method $path",); status=404)
end

# a file from public/; unknown paths (and ../ escapes) get index.html
function static_file(path::AbstractString)
    relative = lstrip(URIs.unescapeuri(path), '/')
    file = normpath(joinpath(PUBLIC_DIR, isempty(relative) ? "index.html" : relative))
    inside = startswith(file, PUBLIC_DIR * Base.Filesystem.path_separator)
    if !(inside && isfile(file))
        file = joinpath(PUBLIC_DIR, "index.html")
        isfile(file) || return HTTP.Response(500, ["Content-Type" => "text/plain"], "ui not built: run pnpm build in web/")
    end
    content_type = get(MIME_TYPES, lowercase(splitext(file)[2]), "application/octet-stream")
    # vite fingerprints asset names, so they can be cached forever
    cache = occursin("/assets/", file) ? "public, max-age=31536000, immutable" : "no-cache"
    return HTTP.Response(200, ["Content-Type" => content_type, "Cache-Control" => cache], read(file))
end

# one request at a time on the shared model; bad input comes back as a json 400
function handle(request::HTTP.Request)
    try
        return lock(() -> route(request), STATE_LOCK)
    catch exception
        exception isa InterruptException && rethrow()
        message = exception isa Union{ArgumentError, ErrorException} ? exception.msg : sprint(showerror, exception)
        return json_response((error=message,); status=400)
    end
end

# load a model (default: examples/e_coli_core.json) and serve the gui until interrupted
function serve(; model=nothing, host::AbstractString="127.0.0.1", port::Integer=8000)
    STATE[] = model === nothing ? load_example(DEFAULT_EXAMPLE) : load_model(model)
    println("gem-stone ready at http://$host:$port; model: $(STATE[].id)")
    flush(stdout)
    HTTP.serve(handle, host, port; max_body_bytes=MAX_UPLOAD_BYTES)
end

# entry point for run.jl: optional model path, PORT from the environment
function main(args=ARGS)
    port = parse(Int, get(ENV, "PORT", "8000"))
    serve(; model=isempty(args) ? nothing : first(args), port=port)
end
