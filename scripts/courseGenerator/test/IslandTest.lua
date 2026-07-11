require('include')
lu.EPS = 0.01

FSDensityMapUtil = {}
function FSDensityMapUtil.getFieldDataAtWorldPosition(x, y, z)
    -- an island is a 100x100 square in the middle of the field
    if math.abs(x) <= 50 and math.abs(z) <= 50 then
        return false, 0
    end
    return true, 0
end

function testIsland()
    local boundary = Polygon({Vertex(-100, -100), Vertex(100, -100), Vertex(100, 100), Vertex(-100, 100)})
    local field = CourseGenerator.Field('test', 1, boundary)
    local islandVertices = CourseGenerator.Island.findIslands(field)
    -- The island spans |x| <= 50 and |z| <= 50 (inclusive) and is scanned on a 1 m
    -- grid, giving 101 x 101 = 10201 vertices (both boundary rows/columns at +/-50
    -- are on the island). All are off-field with no duplicates.
    lu.assertEquals(#islandVertices, 10201)
end
os.exit(lu.LuaUnit.run())
