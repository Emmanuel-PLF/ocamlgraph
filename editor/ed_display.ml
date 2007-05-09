
open Format
open Ed_hyper
open Ed_graph

let debug = ref false


(* Original window size *)
let (w,h)= (600.,600.)


(* GTK to hyperbolic coordinates *)

let to_turtle(x,y)=
  ((float x*.(2./.w) -. 1.),(1. -. float y *.(2./.h)))
(*  ((float x*.(2./.w) ),(float y *.(2./.h) ))*)

(* Hyperbolic to GTK coordinates *)

let from_turtle (x,y) =
  let xzoom = (w/.2.)
  and yzoom = (h/.2.) in
  (truncate (x*.xzoom +. xzoom), truncate(yzoom -. y*.yzoom))

(* Where to start the graph drawing *)

let start_point = to_turtle (truncate(w/.2.), truncate(h/.2.))

let origine =ref start_point



(* GTK *)

(* Current point in Hyperbolic view *)
let current_point = ref (0,0)


(* Change current point *)
let moveto_gtk x y = current_point := (x,y)


(* Change current point with turtle coordinates *)
let tmoveto_gtk turtle = 
  let (x,y)= from_turtle turtle.pos in
  moveto_gtk x y

(* Create a turtle with origine's coordinates *)
let make_origine_turtle () =
  let (x,y) = let (x,y) = !origine in (truncate x, truncate y) in  
  moveto_gtk  x y;
  make_turtle !origine 0.0


(* Append turtle coordinates to line, set current point and return the "new" line *)
let tlineto_gtk turtle line =
  tmoveto_gtk turtle; 
  let (x,y) = !current_point in
  List.append line [(float x); (float y) ] 


(* Set ellipse coordinate to turtle's and set current point too *)
let tdraw_string_gtk turtle (ellipse : GnoCanvas.ellipse) =
  tmoveto_gtk turtle;  
  let (x,y) = !current_point in
  (*            debug            *)
  if !debug then Format.eprintf "tdraw_string_gtk x=%d y=%d@." x y;
  (*            /debug            *)
  ellipse#parent#move ~x:(float x) ~y:(float y);
  ellipse#parent#set  [`X (float x); `Y (float y)]


(* Set line points for a distance with a number of steps, 
   set current point to last line's point, by side-effect of tlineto_gtk,
   and return the final turtle *)
let set_successor_edge turtle distance steps line =
  let d = distance /. (float steps) in
  let rec list_points turtle liste = function
    | 0 -> (turtle,liste)
    | n ->let turt = advance turtle d in
      list_points turt (tlineto_gtk turt liste) (n-1)
  in
  let start = 
    let (x,y) = from_turtle turtle.pos in [(float x); (float y)] in 
  let turtle,lpoints = list_points turtle start steps in
  (*            debug            *)
  if !debug 
  then
    (let ltext=
      let rec string_of_list = function
	|[]->""
	|e::l->(string_of_float e)^" "^string_of_list l
      in string_of_list lpoints in
     Format.eprintf "taille %d %s @." (List.length lpoints) ltext);
  (*            /debug            *)
  let points = Array.of_list lpoints in
  line#set [`POINTS points];
  turtle

let set_intern_edge tv tw bpath line =
  let (x,y) = let (x ,y ) = from_turtle tv.pos in ((float_of_int x),(float_of_int y)) in
  let (x',y') = let (x',y') = from_turtle tw.pos in ((float_of_int x'),(float_of_int y')) in
  let rate = 1.95 in
  GnomeCanvas.PathDef.reset bpath;
  GnomeCanvas.PathDef.moveto bpath x y ;
  GnomeCanvas.PathDef.curveto bpath ((x+. x')/.rate) ((y +. y')/.rate) 
                                    ((x  +.x')/.rate) ((y +. y')/.rate)
                                    x' y';
  line#set [`BPATH bpath]



(* table of all nodes *)

module H = Hashtbl.Make(G.V)

let ellipses = H.create 97

let init_ellipses canvas =
  H.clear ellipses;
  G.iter_vertex
    (fun v -> 
       let s = string_of_label v in
       let (w,h) = (40,20) in
       let node_group = GnoCanvas.group ~x:0.0 ~y:0.0 canvas in
       let ellipse = GnoCanvas.ellipse 
	 ~props:[ `X1  ( float_of_int (-w/2)); `Y1 (float_of_int (-h/2)); 
		  `X2  (float_of_int (w/2)) ; `Y2 ( float_of_int (h/2)) ;
		  `FILL_COLOR "grey" ; `OUTLINE_COLOR "black" ; 
		  `WIDTH_PIXELS 0 ] node_group  
       in
       let texte = GnoCanvas.text ~props:[`X 0.0; `Y 0.0 ; `TEXT s;  
					  `FILL_COLOR "blue"] node_group
       in
       let w2 = texte#text_width in
       if w2 > float_of_int w
       then
	 ellipse#set [ `X1  (-.( w2+.6.)/.2.); `X2 ((w2+.6.)/.2.)];
       node_group#hide();
       H.add ellipses v ellipse 
    )
    !graph
    
let tdraw_string_gtk v turtle canvas =
  let ellipse = H.find ellipses v in
  tdraw_string_gtk turtle ellipse;
  ellipse
   

(* tables of existing graphical edges *)

module H2 = 
  Hashtbl.Make
    (struct 
      type t = G.V.t * G.V.t
      let hash (v,w) = Hashtbl.hash (G.V.hash v, G.V.hash w)
      let equal (v1,w1) (v2,w2) = G.V.equal v1 v2 && G.V.equal w1 w2 
    end)

(* two tables for two types of edge :
   successor_edges = edges with successor of root
   intern_edges = edges between  successors of root *)
let successor_edges = H2.create 97
let intern_edges = H2.create 97


(* draws but don't show intern edges, and return a couple bpath (gtk_object), and line (gtw_widget)*)
let draw_intern_edge vw tv tw canvas =
  (*            debug            *)
  if  !debug
  then ( let (v,w)= let (v,w) = vw in (string_of_label v, string_of_label w) in
      eprintf "tortue %s \t tortue %s@." v w);
  (*            /debug            *)
  let bpath,line = 
    try
      let _,line as pl = H2.find intern_edges vw in
      pl
    with Not_found ->
      let bpath = GnomeCanvas.PathDef.new_path () in
      let line = GnoCanvas.bpath canvas
	~props:[ `BPATH bpath ; `OUTLINE_COLOR "SlateGrey" ; `WIDTH_PIXELS 1 ] in
      line#lower_to_bottom ();
      H2.add intern_edges vw (bpath,line);
      bpath,line
  in
  set_intern_edge tv tw bpath line;
  bpath,line


let draw_successor_edge vw t distance etapes canvas =
 let line =
    try
      H2.find successor_edges vw
    with Not_found ->
      let color = "black" in 
      let l = GnoCanvas.line canvas ~props:[ `FILL_COLOR color ;
					     `WIDTH_PIXELS 1; `SMOOTH true] 
      in
      H2.add successor_edges vw l;
      l
 in
 set_successor_edge t distance etapes line

let color_change_intern_edge color node = 
  G.iter_edges
    (fun _ w ->
       try
	 let _,n = H2.find intern_edges (node,w) in
	 n#set [`OUTLINE_COLOR color]
       with Not_found ->
	 try
	   let _,n = H2.find intern_edges (w,node) in
	   n#set [`OUTLINE_COLOR color]
	 with Not_found ->
	   ()
    )
  !graph


let color_change_direct_edge color node = 
  G.iter_succ
    (fun w ->
       try
	 let n = H2.find successor_edges (node,w) in
	 n#set [`FILL_COLOR color]
       with Not_found ->
	 try
	   let n = H2.find successor_edges (w,node) in
	   n#set [`FILL_COLOR color]
	 with Not_found ->
	   ()
    )
    !graph node
  

let draw_graph canvas =
  (* nodes *)
  G.iter_vertex
    (fun v -> 
      let l = G.V.label v in
      if l.visible = Visible then 
	let ellipse = tdraw_string_gtk v l.turtle canvas in 
	ellipse#parent#show()
      else  (H.find ellipses v)#parent#hide()
    )
    !graph;

  (* succ edges *)
  G.iter_succ
    ( fun v ->
	
    )
    !root !graph;


  (* intern edges *)
  G.iter_edges
    (fun v w ->
      let labv = G.V.label v in
      let labw = G.V.label w in
      let lv = labv.depth in
      let tv = labv.turtle in
      let lw = labw.depth in
      let tw = labw.turtle in
      if labv.visible = Visible && labw.visible = Visible && 
	 abs (lw - lv) <> 1 && (lv <> 0 || lw <> 0) 
      then begin
	(*            debug            *)
	if !debug 
	then (Format.eprintf "tortue : %s\t\t\t tortue : %s@." 
		(string_of_label v) (string_of_label w);
	      let (x ,y ) = from_turtle tv.pos and (x',y') = from_turtle tw.pos in
	      Format.eprintf "pos  x:%d y:%d \t pos x:%d y:%d@." x y x' y';);
	(*            /debug           *)
	let _,line = draw_intern_edge (v,w) tv tw canvas in
	line#show();

      end else
	try let _,line = H2.find intern_edges (v,w) in line#hide () with Not_found -> ()
    ) 
    !graph




let reset_display canvas =
init_ellipses canvas
