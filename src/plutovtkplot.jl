"""
Structure containig plot information. 
In particular it contains dict of data sent to javascript.
"""
mutable struct PlutoVTKPlot  <: AbstractPlutoVistaBackend
    # command list passed to javascript
    jsdict::Dict{String,Any}

    # size in screen coordinates
    w::Float64
    h::Float64

    # update of a already created plot ?

    update::Bool

    args
    
    # uuid for identifying html element
    uuid::UUID
    PlutoVTKPlot(::Nothing)=new()
end

"""
````
    PlutoVTKPlot(;resolution=(300,300))
````

Create a vtk plot with given resolution in the notebook.
"""
function PlutoVTKPlot(;resolution=(300,300), kwargs...)
    p=PlutoVTKPlot(nothing)
    p.uuid=uuid1()
    p.jsdict=Dict{String,Any}("cmdcount" => 0,"cbar" => 0)
    p.w=resolution[1]
    p.h=resolution[2]

    default_args=(title="",
                  clear=false)

    p.args=merge(default_args,kwargs)

    
    p.update=false
    p
end


"""
    Base.show(io::IO,::MIME"text/html",p::PlutoVTKPlot)

Show plot in html. This creates a vtk.js based renderer along with a canvas
for handling the colorbar.
"""
function Base.show(io::IO, ::MIME"text/html", p::PlutoVTKPlot)
    plutovtkplot = read(joinpath(@__DIR__, "..", "assets", "plutovtkplot.js"), String)
    canvascolorbar = read(joinpath(@__DIR__, "..", "assets", "canvascolorbar.js"), String)
    uuidcbar="$(p.uuid)"*"cbar"
    div=""
    if !p.update
    div="""
        <p>
        <div style="white-space:nowrap;">
        <div id="$(p.uuid)" style= "width: $(p.w)px; height: $(p.h)px; display: inline-block; "></div>
        <canvas id="$(uuidcbar)" width=60, height="$(p.h)"  style="display: inline-block; "></canvas>
        </div>
        </p>
    """
    end
    result="""
        <script type="text/javascript" src="https://unpkg.com/vtk.js@19"></script>
        <script>
        $(plutovtkplot)
        $(canvascolorbar)
        const jsdict = $(Main.PlutoRunner.publish_to_js(p.jsdict))
        plutovtkplot("$(p.uuid)",jsdict,invalidation)
        canvascolorbar("$(uuidcbar)",20,$(p.h),jsdict)        
        </script>
        """
     p.update=true
     write(io,result*div)
end



"""
    axis3d!(vtkplot)
Add 3D coordinate system axes to the plot.
Sets camera handling to 3D mode.
"""
function axis3d!(p::PlutoVTKPlot)
    command!(p,"axis")
    parameter!(p,"cam","3D")
end

"""
    axis2d!(vtkplot)
Add 2D coordinate system axes to the plot.
Sets camera handling to 2D mode.
"""
function axis2d!(p::PlutoVTKPlot)
    command!(p,"axis")
    parameter!(p,"cam","2D")
end

"""
       vtkpolys(tris; offset=0)
Set up  polygon (triangle) data for vtk. 
Coding is   [3, i11, i12, i13,   3 , i21, i22 ,i23, ...]
Careful: js indexing counts from zero.
"""
function vtkpolys(tris; offset=0)
    ipoly=1
    ntri=size(tris,2)
    off=offset-1
    polys=Vector{Int32}(undef,4*ntri)
    for itri=1:ntri
        polys[ipoly] = 3
        polys[ipoly+1] = tris[1,itri]+off
        polys[ipoly+2] = tris[2,itri]+off
        polys[ipoly+3] = tris[3,itri]+off
        ipoly+=4
    end
    polys
end


"""
    outline!(p::PlutoVTKPlot,pts,faces,facemarkers,facecolormap,nbregions,xyzmin,xyzmax;alpha=0.1)

Plot transparent outline of grid boundaries.
"""
function outline!(p::PlutoVTKPlot,pts,faces,facemarkers,facecolormap,nbregions,xyzmin,xyzmax;alpha=0.1)
    bregpoints0,bregfacets0=GridVisualize.extract_visible_bfaces3D(pts,faces,facemarkers,nbregions,
                                                                   xyzmax,
                                                                   primepoints=hcat(xyzmin,xyzmax)
                                                                   )
    bregpoints=hcat([reshape(reinterpret(Float32,bregpoints0[i]),(3,length(bregpoints0[i]))) for i=1:nbregions]...)
    bregfacets=vcat([vtkpolys(reshape(reinterpret(Int32,bregfacets0[i]),(3,length(bregfacets0[i]))),
                              offset= ( i==1 ? 0 : sum(k->length(bregpoints0[k]),1:i-1) ) )
                     for i=1:nbregions]...)
    bfacemarkers=vcat([fill(i,length(bregfacets0[i])) for i=1:nbregions]...)
    
    if typeof(facecolormap)==Symbol
        facecmap=colorschemes[facecolormap]
    else
        facecmap=ColorScheme(facecolormap)
    end
    facergb=reinterpret(Float64,get(facecmap,bfacemarkers,(1,size(facecmap))))
    nfaces=length(facergb)÷3
    facergba=zeros(UInt8,nfaces*4)
    irgb=0
    irgba=0
    for i=1:nfaces
        facergba[irgba+1]=UInt8(floor(facergb[irgb+1]*255))
        facergba[irgba+2]=UInt8(floor(facergb[irgb+2]*255))
        facergba[irgba+3]=UInt8(floor(facergb[irgb+3]*255))
        facergba[irgba+4]=UInt8(floor(alpha*255))
        irgb+=3
        irgba+=4
    end
    parameter!(p,"opolys",bregfacets)
    parameter!(p,"opoints",vec(bregpoints))
    parameter!(p,"ocolors",facergba)
    
end



"""
     tricontour!(p::PlutoVTKPlot,pts, tris,f; colormap, levels, limits)

Plot piecewise linear function on  triangular grid given as "heatmap".
Isolines can be given as a number or as a range.
"""
function tricontour!(p::PlutoVTKPlot, pts, tris,f;kwargs...)

    default_args=(colormap=:viridis, levels=0, limits=:auto)
    args=merge(p.args,default_args)
    args=merge(args,kwargs)

    colormap=args[:colormap]

    
    p.jsdict=Dict{String,Any}("cmdcount" => 0)


    command!(p,"tricontour")

    levels,crange=GridVisualize.isolevels(args,f)

    parameter!(p,"points",vec(vcat(pts,zeros(eltype(pts),length(f))')))
    parameter!(p,"polys",vtkpolys(tris))

    rgb=reinterpret(Float64,get(colorschemes[colormap],f,crange))
    parameter!(p,"colors",UInt8.(floor.(rgb*255)))

    parameter!(p,"isopoints","none")
    parameter!(p,"isolines","none")
    
    
    iso_pts=GridVisualize.marching_triangles(pts,tris,f,collect(levels))
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
    
    # It seems a colorbar is best drawn via canvas...
    # https://github.com/Kitware/vtk-js/issues/1621
    bar_stops=collect(0:0.01:1)
    bar_rgb=reinterpret(Float64,get(colorschemes[colormap],bar_stops,(0,1)))
    bar_rgb=UInt8.(floor.(bar_rgb*255))
    p.jsdict["cbar"]=1
    p.jsdict["cstops"]=bar_stops
    p.jsdict["colors"]=bar_rgb
    p.jsdict["levels"]=collect(levels)

    axis2d!(p)
    p
end

"""
     contour!(p::PlutoVTKPlot,X,Y,f; colormap, levels)

Plot piecewise linear function on  triangular grid created from the tensor product of X and Y arrays as "heatmap".
Levels can be given as a number or as a range.
"""
contour!(p::PlutoVTKPlot,X,Y,f; kwargs...)=tricontour!(p,triang(X,Y)...,vec(f);kwargs...)


"""
     tetcontour!(p::PlutoVTKPlot,pts, tets,f; colormap, flevel, xplane, yplane, zplane)

Plot isosurface given by `flevel` and contour maps on planes given by the `*plane` parameters
for piecewise linear function on  tetrahedral mesh. 
"""
function tetcontour!(p::PlutoVTKPlot, pts, tets,func; kwargs...)

    default_args=(colormap=:viridis,
                  levels=5,
                  limits=:auto,
                  faces=nothing,
                  facemarkers=nothing,
                  facecolormap=nothing,
                  xplanes=[prevfloat(Inf)],
                  yplanes=[prevfloat(Inf)],
                  zplanes=[prevfloat(Inf)],
                  levelalpha=0.25,
                  outlinealpha=0.1)
    args=merge(p.args,default_args)
    args=merge(args,kwargs)


    levels,crange=GridVisualize.isolevels(args,func)

    colormap=args[:colormap]
    faces=args[:faces]
    facemarkers=args[:facemarkers]
    facecolormap=args[:facecolormap]

    p.jsdict=Dict{String,Any}("cmdcount" => 0)
    command!(p,"tetcontour")
    xyzmin=zeros(3)
    xyzmax=ones(3)

    nbregions= facemarkers==nothing ? 0 :  maximum(facemarkers)

    if faces!=nothing && nbregions==0
        nbregions=1
        facemarkers=fill(Int32(1),size(faces,2))
    end

    if facecolormap==nothing
        facecolormap=GridVisualize.bregion_cmap(nbregions)
    end
        
    @views for idim=1:3
        xyzmin[idim]=minimum(pts[idim,:])
        xyzmax[idim]=maximum(pts[idim,:])
    end


    xplanes=args[:xplanes]
    yplanes=args[:yplanes]
    zplanes=args[:zplanes]    

    
        
    cpts0,faces0,values=GridVisualize.marching_tetrahedra(pts,tets,func,
                                                          primepoints=hcat(xyzmin,xyzmax),
                                                          primevalues=crange,
                                                          GridVisualize.makeplanes(xyzmin,xyzmax,xplanes,yplanes,zplanes),
                                                          levels;
                                                          tol=0.0
                                                          )

    cfaces=reshape(reinterpret(Int32,faces0),(3,length(faces0)))
    cpts=copy(reinterpret(Float32,cpts0))
    parameter!(p,"points",cpts)
    parameter!(p,"polys",vtkpolys(cfaces))
    nan_replacement=0.5*(crange[1]+crange[2])
    for i=1:length(values)
        if isnan(values[i]) || isinf(values[i])
            values[i]=nan_replacement
        end
    end
    # nan_replacement=0.0
    # for i=1:length(cpts)
    #     if isnan(cpts[i]) || isinf(cpts[i])
    #         cpts[i]=nan_replacement
    #     end
    # end

    crange=(Float64(crange[1]),Float64(crange[2]))
    rgb=reinterpret(Float64,get(colorschemes[colormap],values,crange))
    

    
    if args[:levelalpha]>0
        nfaces=length(rgb)÷3
        rgba=zeros(UInt8,nfaces*4)
        irgb=0
        irgba=0
        for i=1:nfaces
            rgba[irgba+1]=UInt8(floor(rgb[irgb+1]*255))
            rgba[irgba+2]=UInt8(floor(rgb[irgb+2]*255))
            rgba[irgba+3]=UInt8(floor(rgb[irgb+3]*255))
            rgba[irgba+4]=UInt8(floor(args[:levelalpha]*255))
            irgb+=3
            irgba+=4
        end
        parameter!(p,"transparent",1)
        parameter!(p,"colors",rgba)
    else
        parameter!(p,"transparent",0)
        parameter!(p,"colors",UInt8.(floor.(rgb*255)))
    end        

    # It seems a colorbar is best drawn via canvas...
    # https://github.com/Kitware/vtk-js/issues/1621
    bar_stops=collect(0:0.01:1)
    bar_rgb=reinterpret(Float64,get(colorschemes[colormap],bar_stops,(0,1)))
    bar_rgb=UInt8.(floor.(bar_rgb*255))
    p.jsdict["cbar"]=1
    p.jsdict["cstops"]=bar_stops
    p.jsdict["colors"]=bar_rgb
    p.jsdict["levels"]=vcat([crange[1]],levels,[crange[2]])


    if args[:outlinealpha]>0 && faces!=nothing
        parameter!(p,"outline",1)
        outline!(p,pts,faces,facemarkers,facecolormap,nbregions,xyzmin,xyzmax;alpha=args[:outlinealpha])
    else
        parameter!(p,"outline",0)
    end

    axis3d!(p)
    p
    
end




"""
     trimesh!(p::PlutoVTKPlot,pts, tris;markers, colormap, edges, edgemarkers, edgecolormap)

Plot  triangular grid with optional region and boundary markers.
"""
function trimesh!(p::PlutoVTKPlot,pts, tris; kwargs...)

    default_args=(markers=nothing,
                  colormap=nothing,
                  edges=nothing,
                  edgemarkers=nothing,
                  edgecolormap=nothing)
    
    args=merge(p.args,default_args)
    args=merge(args,kwargs)
    
    colormap=args[:colormap]
    markers=args[:markers]
    edgemarkers=args[:edgemarkers]
    edgecolormap=args[:edgecolormap]
    edges=args[:edges]

    ntri=size(tris,2)
    command!(p,"trimesh")
    zcoord=zeros(size(pts,2))
    parameter!(p,"points",vec(vcat(pts,zcoord')))
    parameter!(p,"polys",vtkpolys(tris))



    
    if markers!=nothing
        nregions=maximum(markers)
        if colormap==nothing
            colormap=GridVisualize.region_cmap(nregions)
        end
        if typeof(colormap)==Symbol
            cmap=colorschemes[colormap]
        else
            cmap=ColorScheme(colormap)
        end
        rgb=reinterpret(Float64,get(cmap,markers,(1,size(cmap))))
        parameter!(p,"colors",UInt8.(floor.(rgb*255)))

        bar_stops=collect(1:size(cmap))
        bar_rgb=reinterpret(Float64,get(cmap,bar_stops,(1,size(cmap))))
        bar_rgb=UInt8.(floor.(bar_rgb*255))
        p.jsdict["cbar"]=2
        p.jsdict["cstops"]=bar_stops
        p.jsdict["colors"]=bar_rgb
        p.jsdict["levels"]=collect(1:size(cmap))
        
    else
        parameter!(p,"colors","none")
    end
    
    if edges!=nothing
        nedges=size(edges,2)
        lines=Vector{UInt32}(undef,3*nedges)
        iline=0
        for i=1:nedges
            lines[iline+1]=2
            lines[iline+2]=edges[1,i]-1  #  0-1 discrepancy between jl and js...
            lines[iline+3]=edges[2,i]-1
            iline=iline+3
        end
        parameter!(p,"lines",lines)
        
        if edgemarkers!=nothing
            (fmin,nbregions)=Int64.(extrema(edgemarkers))
            if edgecolormap==nothing
                edgecolormap=GridVisualize.bregion_cmap(nbregions)
            end
            if typeof(edgecolormap)==Symbol
                ecmap=colorschemes[edgecolormap]
            else
                ecmap=ColorScheme(edgecolormap)
            end
            edgergb=reinterpret(Float64,get(ecmap,edgemarkers,(1,size(ecmap))))
            parameter!(p,"linecolors",UInt8.(floor.(edgergb*255)))

            ebar_stops=collect(1:size(ecmap))
            ebar_rgb=reinterpret(Float64,get(ecmap,ebar_stops,(1,size(ecmap))))
            ebar_rgb=UInt8.(floor.(ebar_rgb*255))
            p.jsdict["ecstops"]=ebar_stops
            p.jsdict["ecolors"]=ebar_rgb
            p.jsdict["elevels"]=collect(1:size(ecmap))
        else
            parameter!(p,"linecolors","none")
        end
    else
        parameter!(p,"lines","none")
        parameter!(p,"linecolors","none")
    end
    
    
    
    
    axis2d!(p)
    p
end


"""
     tetmesh!(p::PlutoVTKPlot,pts, tris;markers, colormap, faces, facemarkers, facecolormap,xplane,yplane,zplane, outline, alpha)

Plot parts of tetrahedral mesh below the planes given by the `*plane` parameters.
"""
function tetmesh!(p::PlutoVTKPlot, pts, tets;kwargs...)

    default_args=(markers=nothing,
                  colormap=nothing,
                  faces=nothing,
                  facemarkers=nothing,
                  facecolormap=nothing,
                  xplanes=[prevfloat(Inf)],
                  yplanes=[prevfloat(Inf)],
                  zplanes=[prevfloat(Inf)],
                  outlinealpha=0.1)
    
    args=merge(p.args,default_args)
    args=merge(args,kwargs)
    
    markers=args[:markers]
    colormap=args[:colormap]
    faces=args[:faces]
    facemarkers=args[:facemarkers]
    facecolormap=args[:facecolormap]

    xplane=args[:xplanes][1]
    yplane=args[:yplanes][1]
    zplane=args[:zplanes][1]
    
    


    ntet=size(tets,2)
    command!(p,"tetmesh")
    nregions=  markers==nothing  ? 0 : maximum(markers)
    nbregions= facemarkers==nothing ? 0 :  maximum(facemarkers)

        
    if nregions==0
        nregions=1
        markers=fill(Int32(1),ntet)
    end

    if faces!=nothing && nbregions==0
        nbregions=1
        facemarkers=fill(Int32(1),size(faces,2))
    end


    if colormap==nothing
        colormap=GridVisualize.region_cmap(nregions)
    end

    if facecolormap==nothing
        facecolormap=GridVisualize.bregion_cmap(nbregions)
    end


    
    xyzmin=zeros(3)
    xyzmax=ones(3)

    @views for idim=1:3
        xyzmin[idim]=minimum(pts[idim,:])
        xyzmax[idim]=maximum(pts[idim,:])
    end

    
    xyzcut=[xplane,yplane,zplane]

    regpoints0,regfacets0=GridVisualize.extract_visible_cells3D(pts,tets,markers,nregions,
                                                                xyzcut,
                                                                primepoints=hcat(xyzmin,xyzmax)
                                                                )
    
    points=hcat([reshape(reinterpret(Float32,regpoints0[i] ),(3,length(regpoints0[i] ))) for i=1:nregions]...)
    facets=vcat([vtkpolys(reshape(reinterpret(Int32,regfacets0[i]),(3,length(regfacets0[i])))) for i=1:nregions]...)

    
    regmarkers=vcat([fill(i,length(regfacets0[i])) for i=1:nregions]...)

    if typeof(colormap)==Symbol
        cmap=colorschemes[colormap]
    else
        cmap=ColorScheme(colormap)
    end
    rgb=reinterpret(Float64,get(cmap,regmarkers,(1,size(cmap))))
    nfaces=length(rgb)÷3

    
    bar_stops=collect(1:size(cmap))
    bar_rgb=reinterpret(Float64,get(cmap,bar_stops,(1,size(cmap))))
    bar_rgb=UInt8.(floor.(bar_rgb*255))
    p.jsdict["cbar"]=2
    p.jsdict["cstops"]=bar_stops
    p.jsdict["colors"]=bar_rgb
    p.jsdict["levels"]=collect(1:size(cmap))
    
    
    if faces!=nothing
        bregpoints0,bregfacets0=GridVisualize.extract_visible_bfaces3D(pts,faces,facemarkers,nbregions,
                                                                       xyzcut,
                                                                       primepoints=hcat(xyzmin,xyzmax)
                                                                       )
        bregpoints=hcat([reshape(reinterpret(Float32,bregpoints0[i]),(3,length(bregpoints0[i]))) for i=1:nbregions]...)
        bregfacets=vcat([vtkpolys(reshape(reinterpret(Int32,bregfacets0[i]),(3,length(bregfacets0[i]))),
                                  offset= size(points,2) + ( i==1 ? 0 : sum(k->length(bregpoints0[k]),1:i-1) ) )
                                  for i=1:nbregions]...)
        bfacemarkers=vcat([fill(i,length(bregfacets0[i])) for i=1:nbregions]...)

        if typeof(facecolormap)==Symbol
            facecmap=colorschemes[facecolormap]
        else
            facecmap=ColorScheme(facecolormap)
        end
        facergb=reinterpret(Float64,get(facecmap,bfacemarkers,(1,size(facecmap))))
        facets=vcat(facets,bregfacets)
        points=hcat(points,bregpoints)
        rgb=vcat(rgb,facergb)

        ecmap=facecmap
        ebar_stops=collect(1:size(ecmap))
        ebar_rgb=reinterpret(Float64,get(ecmap,ebar_stops,(1,size(ecmap))))
        ebar_rgb=UInt8.(floor.(ebar_rgb*255))
        p.jsdict["ecstops"]=ebar_stops
        p.jsdict["ecolors"]=ebar_rgb
        p.jsdict["elevels"]=collect(1:size(ecmap))
    end

    if args[:outlinealpha]>0 && faces!=nothing
        parameter!(p,"outline",1)
        outline!(p,pts,faces,facemarkers,facecolormap,nbregions,xyzmin,xyzmax;alpha=args[:outlinealpha])
    else
        parameter!(p,"outline",0)
    end
    
    parameter!(p,"polys",facets)
    parameter!(p,"points",vec(points))
    parameter!(p,"colors",UInt8.(floor.(rgb*255)))
    axis3d!(p)
    p
end






#####################################
# Experimental part
"""
     triplot!(p::PlutoVTKPlot,pts, tris,f)

Plot piecewise linear function on  triangular grid given by points and triangles
as matrices
"""
function triplot!(p::PlutoVTKPlot,pts, tris,f)
    p.jsdict=Dict{String,Any}("cmdcount" => 0)
    command!(p,"triplot")
    # make 3D points from 2D points by adding function value as
    # z coordinate
    p.jsdict["cbar"]=0
    parameter!(p,"points",vec(vcat(pts,f')))
    parameter!(p,"polys",vtkpolys(tris))
    axis3d!(p)
    p
end


function plot!(p::PlutoVTKPlot,x,y; kwargs...)
    command!(p,"plot")
    n=length(x)
    points=vec(vcat(x',y',zeros(n)'))
    lines=collect(UInt16,0:n)
    lines[1]=n
    parameter!(p,"points",points)
    parameter!(p,"lines",lines)
    parameter!(p,"cam","2D")
    p
end
