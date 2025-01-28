import JSON
import Test

using Test: @test

const filename = only(ARGS)

const dict = JSON.parsefile(filename)

# This catches regressions like https://github.com/JuliaLang/VersionsJSONUtil.jl/pull/32#issuecomment-2617551478
for (k_str, _) in pairs(dict)
    k_ver = VersionNumber(k_str)
    @test k_ver isa VersionNumber
end
