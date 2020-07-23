#= require ./removal

e = up.element

class up.Change.DestroyFragment extends up.Change.Removal

  constructor: (options) ->
    super(options)
    @layer = up.layer.get(options)
    @element = @options.element
    @animation = @options.animation
    @log = @options.log

  execute: ->
    @layer.updateHistory(@options)

    # Save the parent because we sometimes emit up:fragment:destroyed
    # after removing @element.
    @parent = @element.parentNode

    if up.motion.willAnimate(@element, @animation, @options)
      up.fragment.markAsDestroying(@element)
      # If we're animating, we resolve *before* removing the element.
      # The destroy animation will then play out, but the destroying
      # element is ignored by all up.fragment.* functions.
      @emitDestroyed()
      @animate().then(@wipe).then(@onMotionEnd)
    else
      # If we're not animating, we can remove the element and then resolve.
      @wipe()
      @emitDestroyed()
      @onMotionEnd()

    # Don't wait for the animation to end.
    return Promise.resolve()

  animate: ->
    up.motion.animate(@element, @animation, @options)

  wipe: =>
    @layer.asCurrent =>
      up.syntax.clean(@element, { @layer })

      if up.browser.canJQuery()
        # jQuery elements store internal attributes in a global cache.
        # We need to remove the element via jQuery or we will leak memory.
        # See https://makandracards.com/makandra/31325-how-to-create-memory-leaks-in-jquery
        jQuery(@element).remove()
      else
        e.remove(@element)

  emitDestroyed: ->
    up.fragment.emitDestroyed(@element, { @parent, @log })
