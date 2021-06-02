
"""
Structure containig plot information. 
In particular it contains dict of data sent to javascript.
The semantics of the keys is explaind in PlutoCanvasPlot.jl
"""
mutable struct VTKPlot  <: AbstractVistaPlot
    # command list passed to javascript
    jsdict::Dict{String,Any}
    cbdict::Dict{String,Any}

    # size in canvas coordinates
    w::Float64
    h::Float64

    update::Bool
    # uuid for identifying html element
    uuid::UUID
    VTKPlot(::Nothing)=new()
end

"""
````
 VTKPlot(;resolution=(300,300))
````

Create a canvas plot with given resolution in the notebook
and given "world coordinate" range.
"""
function VTKPlot(;resolution=(300,300))
    p=VTKPlot(nothing)
    p.uuid=uuid1()
    p.jsdict=Dict{String,Any}("cmdcount" => 0)
    p.cbdict=Dict{String,Any}("cbar" => 0)

    p.w=resolution[1]
    p.h=resolution[2]
    p.update=false
    p
end


"""
Set up  polygon data for vtk. 
Coding is   [3, i11, i12, i13,   3 , i21, i22 ,i23, ...]
Careful: js indexing counts from zero
"""
function vtkpolys(tris)
    ipoly=1
    ntri=size(tris,2)
    polys=Vector{Int32}(undef,4*ntri)
    for itri=1:ntri
        polys[ipoly] = 3
        polys[ipoly+1] = tris[1,itri]-1
        polys[ipoly+2] = tris[2,itri]-1
        polys[ipoly+3] = tris[3,itri]-1
        ipoly+=4
    end
    polys
end

"""
     triplot!(p::VTKPlot,pts, tris,f)

Plot piecewise linear function on  triangular grid given by points and triangles
as matrices
"""
function triplot!(p::VTKPlot,pts, tris,f)
    command!(p,"triplot")
    p.update=false
    # make 3D points from 2D points by adding function value as
    # z coordinate
    p.cbdict["cbar"]=0
    parameter!(p,"points",vec(vcat(pts,f')))
    parameter!(p,"polys",vtkpolys(tris))
    parameter!(p,"cam","3D")
end



"""
     tricolor!(p::VTKPlot,pts, tris,f; colormap)

Plot piecewise linear function on  triangular grid given as "heatmap" 
"""
function tricolor!(p::VTKPlot,pts, tris,f;cmap=:summer, isolevels=-1:0.2:1)
    command!(p,"tricolor")
    (fmin,fmax)=extrema(isolevels)
    parameter!(p,"points",vec(vcat(pts,zeros(length(f))')))
    parameter!(p,"polys",vtkpolys(tris))

    rgb=reinterpret(Float64,get(colorschemes[cmap],f,(fmin,fmax)))
    parameter!(p,"colors",UInt8.(floor.(rgb*255)))
    parameter!(p,"cam","2D")
    
    iso_pts=GridVisualize.marching_triangles(pts,tris,f,isolevels)
    niso_pts=length(iso_pts)
    iso_pts=vcat(reshape(reinterpret(Float32,iso_pts),(2,niso_pts)),zeros(niso_pts)')
    iso_lines=Vector{UInt32}(undef,niso_pts+Int32(niso_pts//2))

    iline=0
    ipt=0
    for i=1:niso_pts//2
        iso_lines[iline+1]=2
        iso_lines[iline+2]=ipt
        iso_lines[iline+3]=ipt+1
        iline=iline+3
        ipt=ipt+2
    end
    parameter!(p,"isopoints",vec(iso_pts))
    parameter!(p,"isolines",iso_lines)

    bar_stops=collect(0:0.01:1)
    bar_rgb=reinterpret(Float64,get(colorschemes[cmap],bar_stops,(0,1)))
    bar_rgb=UInt8.(floor.(bar_rgb*255))
    p.cbdict["cbar"]=1
    p.cbdict["cstops"]=bar_stops
    p.cbdict["colors"]=bar_rgb
    p.cbdict["levels"]=collect(isolevels)
    
    # It seems a colorbar is best drawn via canvas...
    # https://github.com/Kitware/vtk-js/issues/1621
    p
end

function triupdate!(p::VTKPlot,pts,tris,f)
    command!(p,"triplot")
    # make 3D points from 2D points by adding function value as
    # z coordinate
    p.jsdict["xpoints"]=vec(vcat(pts,f'))
    p.update=true
    p
end


"""
Add 3D coordinate system axes to the plot.
Sets camera handling
to 3D mode.
"""
function axis3d!(p::VTKPlot;
                 xtics=0:1,
                 ytics=0:1,
                 ztics=0:1)
    command!(p,"axis3d")
    parameter!(p,"bounds",[extrema(xtics)..., extrema(ytics)...,extrema(ztics)...])
    parameter!(p,"cam",ztics[1]==ztics[end] ? "2D" : "3D")
end

"""
    Add 2D coordinate system axes to the plot. Sets camera handling
to 2D mode.
"""
axis2d!(p::VTKPlot;kwargs...)=axis3d!(p;ztics=0.0,kwargs...)



"""
Show plot
"""
function Base.show(io::IO, ::MIME"text/html", p::VTKPlot)
    vtkplot = read(joinpath(@__DIR__, "..", "assets", "vtkplot.js"), String)
    colorbar = read(joinpath(@__DIR__, "..", "assets", "colorbar.js"), String)
    uuidcbar="$(p.uuid)"*"cbar"
    result=" "
    if p.update
        result="""
        <script type="text/javascript" src="https://unpkg.com/vtk.js@18"></script>
        <script>
        $(vtkplot)
        const jsdict = $(Main.PlutoRunner.publish_to_js(p.jsdict))
        vtkupdate("$(p.uuid)",jsdict,invalidation)        
        </script>
        """
    else
        result="""
        <script type="text/javascript" src="https://unpkg.com/vtk.js@18"></script>
        <script>
        $(vtkplot)
        $(colorbar)
        const jsdict = $(Main.PlutoRunner.publish_to_js(p.jsdict))
        vtkplot("$(p.uuid)",jsdict,invalidation)
        const cbdict = $(Main.PlutoRunner.publish_to_js(p.cbdict))
        colorbar("$(uuidcbar)",20,$(p.h),cbdict)        
        </script>
        <p>
        <div style="white-space:nowrap;">
        <div id="$(p.uuid)" style= "width: $(p.w)px; height: $(p.h)px; display: inline-block; "></div>
        <canvas id="$(uuidcbar)" width=50, height="$(p.h)"  style="display: inline-block; "></canvas>
        </div>
</p>
        """
    end
    write(io,result)
end



