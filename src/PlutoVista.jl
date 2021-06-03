module PlutoVista
using UUIDs
using Colors
using ColorSchemes
using GridVisualize


include("common.jl")

include("canvas.jl")

export polygon!,linecolor!, fillcolor!
export textcolor!,textsize!,text!
export polyline!,linecolor!
export polygon!,fillcolor!
export axis!
export CanvasColorbar
export plot!
include("vtk.jl")


export plutovista
export triplot!,tricolor!, axis3d!, axis2d!
export triupdate!


include("plotly.jl")

export PlotlyPlot
end # module
