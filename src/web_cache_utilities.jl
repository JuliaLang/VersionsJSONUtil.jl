using Dates: Dates, now, UTC, unix2datetime, TimePeriod, Hour
using URIs: URI

function download_to_cache(filename::String, url::Union{String, URI})
    my_sleep()
    file_path = _hit_file_cache(filename) do file_path
        r = open(io -> HTTP.get(url; response_stream=io), file_path, "w")
        if r.status != 200
            error("Unable to download $(url) to $(filename)")
        end
    end
    return file_path
end

function _hit_file_cache(creator::Function, filename::String, lifetime::TimePeriod = Hour(24))
    cache_dir = abspath(joinpath(@__DIR__, "..", "cache"))
    if !isdir(cache_dir)
        mkpath(cache_dir)
    end

    cache_path = joinpath(cache_dir, filename)
    if isfile(cache_path)
        age = now(UTC) - unix2datetime(stat(cache_path).mtime)
        if age < lifetime
            @debug "Cache hit" filename isfile(cache_path) age Dates.canonicalize(age) lifetime
            return abspath(cache_path)
        else
            @debug "Cache miss. Cache entry found, but stale (too old)" filename isfile(cache_path) age Dates.canonicalize(age) lifetime
        end
    else
        @debug "Cache miss. Cache entry not found" filename isfile(cache_path)
    end

    rm(cache_path; force=true)
    mktempdir() do tmpdir
        tmp_path = joinpath(tmpdir, filename)

        creator(tmp_path)

        if !isfile(tmp_path)
            error("Creator function didn't actually create file: $filename")
        end
        try
            mv(tmp_path, cache_path; force = true)
        catch
            rm(cache_path; force=true)
            rethrow()
        end
    end

    if !isfile(cache_path)
        error("Our mv must have somehow failed for file: $filename")
    end
    # Update the mtime:
    touch(cache_path)

    @debug "Successfully saved new cache entry" filename

    return abspath(cache_path)
end
