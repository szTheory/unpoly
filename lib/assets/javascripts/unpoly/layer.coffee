u = up.util
e = up.element

###**
Layers
======

TODO

@module up.layer
###
up.layer = do ->

  OVERLAY_CLASSES = [
    up.Layer.Modal
    up.Layer.Popup
    up.Layer.Drawer
    up.Layer.Cover
  ]
  OVERLAY_MODES = u.map(OVERLAY_CLASSES, 'mode')
  LAYER_CLASSES = [up.Layer.Root].concat(OVERLAY_CLASSES)

  # TODO: Document up.layer.config
  config = new up.Config ->
    newConfig =
      mode: 'modal'
      any:
        mainTargets: [
          "[up-main='']",
          'main',
          ':layer' # this is <body> for the root layer
        ],
      root:
        mainTargets: ['[up-main~=root]']
        history: true
      overlay:
        mainTargets: ['[up-main~=overlay]']
        openAnimation: 'fade-in'
        closeAnimation: 'fade-out'
        dismissLabel: '×'
        dismissAriaLabel: 'Dismiss dialog'
        dismissable: true
        history: 'auto'
      cover:
        mainTargets: ['[up-main~=cover]']
      drawer:
        mainTargets: ['[up-main~=drawer]']
        backdrop: true
        position: 'left'
        size: 'medium'
        openAnimation: (layer) ->
          switch layer.position
            when 'left' then 'move-from-left'
            when 'right' then 'move-from-right'
        closeAnimation: (layer) ->
          switch layer.position
            when 'left' then 'move-to-left'
            when 'right' then 'move-to-right'
      modal:
        mainTargets: ['[up-main~=modal]']
        backdrop: true
        size: 'medium'
      popup:
        mainTargets: ['[up-main~=popup]']
        position: 'bottom'
        size: 'medium'
        align: 'left'

    for Class in LAYER_CLASSES
      newConfig[Class.mode].Class = Class

    return newConfig

  stack = null

  handlers = []

  isOverlayMode = (mode) ->
    return u.contains(OVERLAY_MODES, mode)

  mainTargets = (mode) ->
    return u.flatMap(modeConfigs(mode), 'mainTargets')

  ###**
  Returns an array of config objects that apply to the given mode name.

  The config objects are in descending order of specificity.
  ###
  modeConfigs = (mode) ->
    if mode == 'root'
      return [config.root, config.any]
    else
      return [config[mode], config.overlay, config.any]
      
  normalizeOptions = (options) ->
    up.migrate.handleLayerOptions?(options)

    if u.isGiven(options.layer) # might be the number 0, which is falsy
      if options.layer == 'swap'
        if up.layer.isRoot()
          options.layer = 'root'
        else
          options.layer = 'new'
          options.currentLayer = 'parent'

      if options.layer == 'new'
        # If the user wants to open a new layer, but does not pass a { mode },
        # we assume the default mode from up.layer.config.mode.
        options.mode ||= config.mode
      else if isOverlayMode(options.layer)
        # We allow passing an overlay mode in { layer }, which will
        # open a new layer with that mode.
        options.mode = options.layer
        options.layer = 'new'
    else
      # If no options.layer is given we still want to avoid updating "any" layer.
      # Other options might have a hint for a more appropriate layer.

      if options.mode
        # If user passes a { mode } option without a { layer } option
        # we assume they want to open a new layer.
        options.layer = 'new'
      else if u.isElementish(options.target)
        # If we are targeting an actual Element or jQuery collection (and not
        # a selector string) we operate in that element's layer.
        options.layer = stack.get(options.target, normalizeLayerOptions: false)
      else if options.origin
        # Links update their own layer by default.
        options.layer = 'origin'
      else
        # If nothing is given, we assume the current layer
        options.layer = 'current'

    options.context ||= {}

    # Remember the layer that was current when the request was made,
    # so changes with `{ layer: 'new' }` will know what to stack on.
    # Note if options.currentLayer is given, up.layer.get('current', options) will
    # return the resolved version of that.
    # TODO: Test this
    options.currentLayer = stack.get('current', u.merge(options, normalizeLayerOptions: false))

  build = (options, transformOptions) ->
    console.log("up.layer.build(%o, %o)", u.copy(options), transformOptions)
    mode = options.mode
    Class = config[mode].Class
    configs = u.reverse(modeConfigs(mode))
    options = u.mergeDefined(configs..., { mode, stack }, options)
    transformOptions?(options)
    return new Class(options)

#  modeClass = (options = {}) ->
#    mode = options.mode ? config.mode
#    config[mode].Class or up.fail("Unknown layer mode: #{mode}")

  openCallbackAttr = (link, attr) ->
    return e.callbackAttr(link, attr, ['layer'])

  closeCallbackAttr = (link, attr) ->
    return e.callbackAttr(link, attr, ['layer', 'value'])

  reset = ->
    config.reset()
    stack.reset()
    handlers = u.filter(handlers, 'isDefault')

  open = (options) ->
    options = u.options(options, layer: 'new', navigate: true)

    # Even if we are given { content } we need to pipe this through up.render()
    # since a lot of options processing is happening there.
    return up.render(options)

  ###**
  This event is emitted after a layer's [location property](/up.Layer#location)
  has changed value.

  This event is also emitted when a layer [without history](/up.Layer#history)
  has reached a new location.

  @param {string} event.location
    The new location URL.
  @event up:layer:location:changed
  @experimental
  ###

  # TODO: Docs for up.layer.ask()
  ask = (options) ->
    return new Promise (resolve, reject) ->
      options = u.merge options,
        onAccepted: (event) -> resolve(event.value)
        onDismissed: (event) -> reject(event.value)
      open(options)

  anySelector = ->
    u.map(LAYER_CLASSES, (Class) -> Class.selector()).join(',')

  up.on 'up:fragment:destroyed', (event) ->
    stack.sync()

  up.on 'up:framework:boot', ->
    stack = new up.LayerStack()

  up.on 'up:framework:reset', reset

  api = u.literal({
    config
    mainTargets
    open
    build
    ask
    normalizeOptions
    openCallbackAttr
    closeCallbackAttr
    anySelector
    get_stack: -> stack
  })

  ###**
  Returns the current layer in the [layer stack](/up.layer.stack).

  The *current* layer is usually the [frontmost layer](/up.layer.front).
  There are however some cases where the current layer is a layer in the background:

  - When an element in a background layer is compiled.
  - When an Unpoly event like `up:request:loaded` is triggered from a background layer.
  - When the event listener was bound to a background layer using `up.Layer#on()`.

  To temporarily change the current layer from your own code, use `up.Layer#asCurrent()`.

  @property up.layer.current
  @param {up.Layer} layer
  @stable
  ###
  u.delegate(api, [
    'get'
    'getAll'
    'root'
    'overlays'
    'current'
    'front'
    'sync'
  ], -> stack)

  u.delegate(api, [
    'accept'
    'dismiss'
    'isRoot'
    'isOverlay'
    'on'
    'off'
    'emit'
    'parent'
    'child'
    'ancestor'
    'descendants'
    'history'
    'location'
    'title'
    'mode'
    'context'
    'element'
    'contains'
    'size'
    'origin'
    'affix'
  ], -> stack.current)

  return api

u.getter up, 'context', -> up.layer.context