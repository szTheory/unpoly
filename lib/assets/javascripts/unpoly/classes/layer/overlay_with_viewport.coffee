#= require ./base
#= require ./overlay

e = up.element

class up.Layer.OverlayWithViewport extends up.Layer.Overlay

  # It makes only sense to have a single body shifter
  @bodyShifter: new up.BodyShifter()

  openNow: (options) ->
    @createElement()
    @element.classList.add('.up-overlay-with-viewport')
    @backdropElement = e.affix(@element, '.up-overlay-backdrop')
    if @dismissable
      @backdropElement.setAttribute('up-dismiss', '')
    @viewportElement = e.affix(@element, '.up-overlay-viewport')
    @frameInnerContent(@viewportElement, options)

    @shiftBody()
    return @startOpenAnimation(options)

  closeNow: (options) ->
    animation = => @startCloseAnimation(options)
    @destroyElement({ animation }).then =>
      @unshiftBody()

  shiftBody: ->
    @constructor.bodyShifter.shift()

  unshiftBody: ->
    @constructor.bodyShifter.unshift()

  startOpenAnimation: (options = {}) ->
    animateOptions = @openAnimateOptions(options)
    viewportAnimation = options.animation ? @evalOption(@openAnimation)
    backdropAnimation = options.backdropAnimation ? @evalOption(@backdropOpenAnimation)

    return @withAnimatingClass =>
      return Promise.all([
        up.animate(@viewportElement, viewportAnimation, animateOptions),
        up.animate(@backdropElement, backdropAnimation, animateOptions),
      ])

  startCloseAnimation: (options = {}) ->
    animateOptions = @closeAnimateOptions(options)
    viewportAnimation = options.animation ? @evalOption(@closeAnimation)
    backdropAnimation = options.backdropAnimation ? @evalOption(@backdropCloseAnimation)

    return @withAnimatingClass =>
      return Promise.all([
        up.animate(@viewportElement, viewportAnimation, animateOptions),
        up.animate(@backdropElement, backdropAnimation, animateOptions),
      ])

#  startCloseAnimation: (options = {}) ->
#    animateOptions = @closeAnimateOptions(options)
#    viewportAnimation = options.animation ? @evalOption(@closeAnimation)
#    backdropAnimation = options.backdropAnimation ? @evalOption(@backdropCloseAnimation)
#
#    viewportDestroyOptions = u.merge(animateOptions, animation: viewportAnimation)
#    backdropDestroyOptions = u.merge(animateOptions, animation: backdropAnimation)
#
#    return @withAnimatingClass =>
#      return Promise.all([
#        up.destroy(@viewportElement, viewportDestroyOptions),
#        up.destroy(@backdropElement, backdropDestroyOptions),
#      ])
