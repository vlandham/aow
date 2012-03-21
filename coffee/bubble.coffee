
node_radius = (node) ->
  radius = 25
  if node.type == "root"
    radius = 50
  else if node.depth < 1
    radius = 10
  else if node.depth < 3
    radius = 20
  radius

titles =
  "freq": ["all the time", "occasionally", "infrequently"]
  "recency": ["currently working together", "worked together recently", "it's been a while"]
  "type": ["collaborators", "vendors", "clients"]

parse_data = (raw_data) ->
  console.log(raw_data)

  data = [get_root(raw_data)]
  if raw_data.list.connections.collaborator
    data = d3.merge([data, raw_data.list.connections.collaborator])
  if raw_data.list.connections.vendor
    data = d3.merge([data, raw_data.list.connections.vendor])
  if raw_data.list.connections.client
    data = d3.merge([data, raw_data.list.connections.client])
  data

get_root = (raw_data) ->
  raw_data.list.root

class BubbleChart
  constructor: (data) ->
    @data = parse_data(data)
    @width = 910
    @height = 600
    @charge_scale = 4.5

    @tooltip = CustomTooltip("bubble_tooltip", 240)

    # locations the nnodes will move towards
    # depending on which view is currently being
    # used
    @center = {x: @width / 2, y: @height / 2 - 40}
    # @centers =
    #   "1":{x: @width / 3, y: @height / 2}
    #   "2":{x: @width / 2, y: @height / 2}
    #   "3":{x: 2 * @width / 3, y: @height / 2}

    @centers =
      "freq":
        "1":{x: @width / 2, y: @height -  @height / 3}
        "2":{x: 2 * @width / 3, y: @height / 3}
        "3":{x: @width / 3, y: @height / 3}
      "recency":
        "1":{x: @width / 3, y: @height / 3}
        "2":{x: 2 * @width / 3, y: @height / 3}
        "3":{x: @width / 2, y: 2 * @height / 3}
      "type":
        "collaborator":{x: @width / 3, y: @height / 3}
        "vendor":{x: 2 * @width / 3, y: @height / 3}
        "client":{x: @width / 2, y: 2 * @height / 3}
    # used when setting up force and
    # moving around nodes
    @layout_gravity = -0.01
    @damper = 0.1

    # these will be set in create_nodes and create_vis
    @vis = null
    @nodes = []
    @force = null
    @circles = null

    # nice looking colors - no reason to buck the trend
    # @fill_color = d3.scale.ordinal()
    #   .domain(["collaborator", "vendor", "client"])
    #   .range(["#d84b2a", "#beccae", "#7aa25c"])

    # use the max total_amount in the data as the max in the scale's domain
    extent = d3.extent(@data, (d) -> d.depth)
    console.log(extent)
    @radius_scale = d3.scale.pow().exponent(0.01).domain([extent[0], extent[1]]).range([1, 10])
    
    this.create_nodes()
    this.create_vis()


  # create node objects from original data
  # that will serve as the data behind each
  # bubble in the vis, then add each node
  # to @nodes to be used later
  create_nodes: () =>

    @data.forEach (d) =>
      node = {}
      d3.keys(d).forEach (k) ->
        node[k] = d[k]
      node.radius = node_radius(d)
      node.x = if d.type == "root" then @center.x else Math.random() * @width
      node.y = if d.type == "root" then @center.y else Math.random() * @height
      node.fixed = if d.type == "root" then true else false
      @nodes.push node

    @nodes.sort (a,b) -> b.value - a.value


  # create svg at #vis and then 
  # create circle representation for each node
  create_vis: () =>
    @vis = d3.select("#vis").append("svg")
      .attr("width", @width)
      .attr("height", @height)
      .attr("id", "svg_vis")

    @circles = @vis.selectAll("circle")
      .data(@nodes, (d) -> d.id)

    # used because we need 'this' in the 
    # mouse callbacks
    that = this

    # radius will be set to 0 initially.
    # see transition below
    @circles.enter().append("circle")
      .attr("r", 0)
      .attr("class", (d) => d.type)
      .attr("id", (d) -> "bubble_#{d.id}")
      .on("mouseover", (d,i) -> that.show_details(d,i,this))
      .on("mouseout", (d,i) -> that.hide_details(d,i,this))

    # Fancy transition to make bubbles appear, ending with the
    # correct radius
    @circles.transition().duration(2000).attr("r", (d) -> d.radius)


  # Charge function that is called for each node.
  # Charge is proportional to the diameter of the
  # circle (which is stored in the radius attribute
  # of the circle's associated data.
  # This is done to allow for accurate collision 
  # detection with nodes of different sizes.
  # Charge is negative because we want nodes to 
  # repel.
  # Dividing by @charge_scale scales down the charge to be
  # appropriate for the visualization dimensions.
  charge: (d) =>
    -Math.pow(d.radius, 2.0) / @charge_scale

  # Starts up the force layout with
  # the default values
  start: () =>
    @force = d3.layout.force()
      .nodes(@nodes)
      .size([@width, @height])

  # Sets up force layout to display
  # all nodes in one circle.
  display_group_all: () =>
    @force.gravity(@layout_gravity)
      .charge(this.charge)
      .friction(0.9)
      .on "tick", (e) =>
        @circles.each(this.move_towards_center(e.alpha))
          .attr("cx", (d) -> d.x)
          .attr("cy", (d) -> d.y)
    @force.start()

    this.hide_titles()

  # Moves all circles towards the @center
  # of the visualization
  move_towards_center: (alpha) =>
    (d) =>
      d.x = d.x + (@center.x - d.x) * (@damper + 0.02) * alpha
      d.y = d.y + (@center.y - d.y) * (@damper + 0.02) * alpha

  # sets the display of bubbles to be separated
  # into each year. Does this by calling move_towards_year
  display_by_frequent: () =>
    this.hide_titles()

    @force.gravity(@layout_gravity)
      .charge(this.charge)
      .friction(0.9)
      .on "tick", (e) =>
        @circles.each(this.move_towards_frequency(e.alpha))
          .attr("cx", (d) -> d.x)
          .attr("cy", (d) -> d.y)
    @force.start()

    this.display_titles("freq")

  display_by_recent: () =>
    this.hide_titles()
    @force.gravity(@layout_gravity)
      .charge(this.charge)
      .friction(0.9)
      .on "tick", (e) =>
        @circles.each(this.move_towards_recency(e.alpha))
          .attr("cx", (d) -> d.x)
          .attr("cy", (d) -> d.y)
    @force.start()

    this.display_titles("recency")

  display_by_type: () =>
    this.hide_titles()
    @force.gravity(@layout_gravity)
      .charge(this.charge)
      .friction(0.9)
      .on "tick", (e) =>
        @circles.each(this.move_towards_pos(e.alpha, "type"))
          .attr("cx", (d) -> d.x)
          .attr("cy", (d) -> d.y)
    @force.start()

    this.display_titles("type")

  move_towards_frequency: (alpha) =>
    (d) =>
      # target = @year_centers[d.year]
      target = @centers["freq"][d.freq]
      return unless target
      d.x = d.x + (target.x - d.x) * (@damper + 0.02) * alpha * 1.1
      d.y = d.y + (target.y - d.y) * (@damper + 0.02) * alpha * 1.1

  move_towards_recency: (alpha) =>
    (d) =>
      # target = @year_centers[d.year]
      target = @centers["recency"][d.recency]
      return unless target
      d.x = d.x + (target.x - d.x) * (@damper + 0.02) * alpha * 1.1
      d.y = d.y + (target.y - d.y) * (@damper + 0.02) * alpha * 1.1


  move_towards_pos: (alpha, type) =>
    (d) =>
      # target = @year_centers[d.year]
      target = @centers[type][d[type]]
      return unless target
      d.x = d.x + (target.x - d.x) * (@damper + 0.02) * alpha * 1.1
      d.y = d.y + (target.y - d.y) * (@damper + 0.02) * alpha * 1.1


  # Method to display year titles
  display_titles: (display_type) =>
    feature_titles = titles[display_type]

    title_cords = [
      {x: (@width / 3) - 20, y: 80}
      {x: (2 * @width / 3) + 20, y: 80}
      {x: @width / 2, y: @height - 60}
    ]

    # title_x = [@width / 3, @width / 2, @width - 160]
    title = @vis.selectAll(".titles")
      .data(feature_titles)

    title.enter().append("text")
      .attr("class", "titles")
      .attr("x", (d,i) => title_cords[i].x )
      .attr("y", (d,i) => title_cords[i].y )
      .attr("text-anchor", "middle")
      .text((d) -> d)

  # Method to hide year titiles
  hide_titles: () =>
    title = @vis.selectAll(".titles").remove()

  show_details: (data, i, element) =>

    d3.select(element).classed("active", true)
    content = ""
    d3.keys(data).forEach (k) ->
      content += "<span class=\"name\">#{k}</span><span class=\"value\"> #{data[k]}</span><br/>"
    @tooltip.showTooltip(content, d3.event)

  hide_details: (data, i, element) =>
    d3.select(element).classed("active", false)
    # d3.select(element).attr("stroke", (d) => d3.rgb(@fill_color(d.group)).darker())
    @tooltip.hideTooltip()

root = exports ? this

$ ->
  chart = null

  render_vis = (csv) ->
    chart = new BubbleChart csv
    chart.start()
    root.display_all()
  root.display_all = () =>
    chart.display_group_all()
  root.display_frequency = () =>
    chart.display_by_frequent()
  root.display_recency = () =>
    chart.display_by_recent()
  root.display_type = () =>
    chart.display_by_type()
  root.toggle_view = (view_type) =>
    if view_type == 'frequency'
      root.display_frequency()
    else if view_type == 'recency'
      root.display_recency()
    else if view_type == 'type'
      root.display_type()
    else
      root.display_all()

  d3.json "data/44.json", render_vis
