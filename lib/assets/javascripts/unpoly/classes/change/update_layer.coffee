#= require ./addition

u = up.util
e = up.element

class up.Change.UpdateLayer extends up.Change.Addition

  constructor: (options) ->
    super(options)
    @layer = options.layer
    @target = options.target
    @origin = options.origin
    @placement = options.placement
    @parseSteps()

  requestAttributes: ->
    @matchPreflight()

    return {
      layer: @layer
      mode: @layer.mode
      context: @layer.context
      target: @bestPreflightSelector(),
    }

  bestPreflightSelector: ->
    @matchPreflight()

    u.map(@steps, 'selector').join(', ') || ':none'

  toString: ->
    "Update \"#{@target}\" in #{@layer}"

  execute: (@responseDoc) ->
    # For each step, find a step.alternative that matches in both the current page
    # and the response document.
    @matchPostflight()

    up.puts('up.render()', "Updating \"#{@target}\" in #{@layer}")

    @options.title = @improveHistoryValue(@options.title, @responseDoc.getTitle())

    # Make sure only the first step will have scroll-related options.
    @setScrollAndFocusOptions()

    if @options.saveScroll
      up.viewport.saveScroll()

    if @options.peel
      @layer.peel()
      # Layer#peel() will manipulate the stack sync.
      # We don't wait for the peeling animation to finish.

    # If either the server or the up.render() caller has provided a new
    # { context } object, we set the layer's context to that object.
    @layer.updateContext(u.pick(@options, ['context']))

    # Change history before compilation, so new fragments see the new location.

    throw "we do want history: false to be irrelevant if title: 'string' is given, yes?"

    @layer.updateHistory(u.pick(@options, ['history', 'location', 'title'])) # layer location changed event soll hier nicht mehr fliegen

    # The server may trigger multiple signals that may cause the layer to close:
    #
    # - Close the layer directly through X-Up-Accept-Layer or X-Up-Dismiss-Layer
    # - Event an event with X-Up-Events, to which a listener may close the layer
    # - Update the location to a URL for which { acceptLocation } or { dismissLocation }
    #   will close the layer.
    #
    # Note that @handleLayerChangeRequests() also calls @abortWhenLayerClosed()
    # if any of these options cause the layer to close.
    @handleLayerChangeRequests()

    swapPromises = @steps.map(@executeStep)

    Promise.all(swapPromises).then =>
      @abortWhenLayerClosed()
      @onRemoved()
      @onAppeared()

    return Promise.resolve()

  executeStep: (step) =>
    # When the server responds with an error, or when the request method is not
    # reloadable (not GET), we keep the same source as before.
    if step.source == 'keep'
      step.source = up.fragment.source(step.oldElement)

    # Remember where the element came from in case someone needs to up.reload(newElement) later.
    up.fragment.setSource(step.newElement, step.source)

    switch step.placement
      when 'swap'
        if keepPlan = @findKeepPlan(step)
          # Since we're keeping the element that was requested to be swapped,
          # there is nothing left to do here, except notify event listeners.
          up.fragment.emitKept(keepPlan)

          @handleFocus(step.oldElement, step)
          @handleScroll(step.oldElement, step)

          return Promise.resolve()

        else
          # This needs to happen before up.syntax.clean() below.
          # Otherwise we would run destructors for elements we want to keep.
          @transferKeepableElements(step)

          parent = step.oldElement.parentNode

          morphOptions = u.merge step,
            beforeStart: ->
              up.fragment.markAsDestroying(step.oldElement)
            afterInsert: =>
              @responseDoc.activateElement(step.newElement, step)
            beforeDetach: =>
              up.syntax.clean(step.oldElement, { @layer })
            afterDetach: ->
              e.remove(step.oldElement) # clean up jQuery data
              up.fragment.emitDestroyed(step.oldElement, parent: parent, log: false)
            scrollNew: =>
              @handleFocus(step.newElement, step)
              @handleScroll(step.newElement, step)

          return up.morph(
            step.oldElement,
            step.newElement,
            step.transition,
            morphOptions
          )

      when 'before', 'after'
        # We're either appending or prepending. No keepable elements must be honored.

        # Text nodes are wrapped in a up-insertion container so we can
        # animate them and measure their position/size for scrolling.
        # This is not possible for container-less text nodes.
        wrapper = e.createFromSelector('up-insertion')
        while childNode = step.newElement.firstChild
          wrapper.appendChild(childNode)

        # Note that since we're prepending/appending instead of replacing,
        # newElement will not actually be inserted into the DOM, only its children.
        if step.placement == 'before'
          step.oldElement.insertAdjacentElement('afterbegin', wrapper)
        else
          step.oldElement.insertAdjacentElement('beforeend', wrapper)

        for child in wrapper.children
          # Compile the new content and emit up:fragment:inserted.
          @responseDoc.activateElement(child, step)

        @handleFocus(wrapper, step)

        # Reveal element that was being prepended/appended.
        # Since we will animate (not morph) it's OK to allow animation of scrolling
        # if options.scrollBehavior is given.
        promise = @handleScroll(wrapper, step)

        # Since we're adding content instead of replacing, we'll only
        # animate newElement instead of morphing between oldElement and newElement
        promise = promise.then -> up.animate(wrapper, step.transition, step)

        # Remove the wrapper now that is has served it purpose
        promise = promise.then -> e.unwrap(wrapper)

        return promise

      else
        up.fail('Unknown placement: %o', step.placement)

  # Returns a object detailling a keep operation iff the given element is [up-keep] and
  # we can find a matching partner in newElement. Otherwise returns undefined.
  #
  # @param {Element} options.oldElement
  # @param {Element} options.newElement
  # @param {boolean} options.keep
  # @param {boolean} options.descendantsOnly
  findKeepPlan: (options) ->
    # Going back in history uses keep: false
    return unless options.keep

    { oldElement, newElement } = options

    # We support these attribute forms:
    #
    # - up-keep             => match element itself
    # - up-keep="true"      => match element itself
    # - up-keep="false"     => don't keep
    # - up-keep=".selector" => match .selector
    if partnerSelector = e.booleanOrStringAttr(oldElement, 'up-keep')
      if partnerSelector == true
        partnerSelector = '&'

      lookupOpts = { layer: @layer, origin: oldElement }

      if options.descendantsOnly
        partner = up.fragment.get(newElement, partnerSelector, lookupOpts)
      else
        partner = up.fragment.subtree(newElement, partnerSelector, lookupOpts)[0]

      if partner && e.matches(partner, '[up-keep]')
        plan =
          oldElement: oldElement # the element that should be kept
          newElement: partner # the element that would have replaced it but now does not
          newData: up.syntax.data(partner) # the parsed up-data attribute of the element we will discard

        unless up.fragment.emitKeep(plan).defaultPrevented
          return plan

  # This will find all [up-keep] descendants in oldElement, overwrite their partner
  # element in newElement and leave a visually identical clone in oldElement for a later transition.
  # Returns an array of keepPlans.
  transferKeepableElements: (step) ->
    keepPlans = []
    if step.keep
      for keepable in step.oldElement.querySelectorAll('[up-keep]')
        if plan = @findKeepPlan(u.merge(step, oldElement: keepable, descendantsOnly: true))
          # plan.oldElement is now keepable

          # Replace keepable with its clone so it looks good in a transition between
          # oldElement and newElement. Note that keepable will still point to the same element
          # after the replacement, which is now detached.
          keepableClone = keepable.cloneNode(true)
          e.replace(keepable, keepableClone)

          # Since we're going to swap the entire oldElement and newElement containers afterwards,
          # replace the matching element with keepable so it will eventually return to the DOM.
          e.replace(plan.newElement, keepable)
          keepPlans.push(plan)

    step.keepPlans = keepPlans

  parseSteps: ->
    @steps = []

    # resolveSelector was already called by up.Change.FromContent
    for simpleTarget in u.splitValues(@target, ',')
      unless simpleTarget == ':none'
        expressionParts = simpleTarget.match(/^(.+?)(?:\:(before|after))?$/) or
          throw up.error.invalidSelector(simpleTarget)

        # Each step inherits all options of this change.
        step = u.merge(@options,
          selector: expressionParts[1]
          placement: expressionParts[2] || @placement || 'swap'
        )

        @steps.push(step)

  matchPreflight: ->
    return if @matchedPreflight

    for step in @steps
      # Try to find fragments matching step.selector within step.layer.
      # Note that step.oldElement might already have been set by @parseSteps().
      step.oldElement ||= up.fragment.get(step.selector, step) or
        throw @notApplicable("Could not find element \"#{@target}\" in current page")

    @resolveOldNesting()

    @matchedPreflight = true

  matchPostflight: ->
    return if @matchedPostflight

    @matchPreflight()

    for step in @steps
      # The responseDoc has no layers.
      step.newElement = @responseDoc.select(step.selector) or
        throw @notApplicable("Could not find element \"#{@target}\" in server response")

    # Only when we have a match in the required selectors, we
    # append the optional steps for [up-hungry] elements.
    if @options.hungry
      @addHungrySteps()

#    # Remove steps when their oldElement is nested inside the oldElement
#    # of another step.
    @resolveOldNesting()

    @matchedPostflight = true

  addHungrySteps: ->
    # Find all [up-hungry] fragments within @layer
    hungries = up.fragment.all(up.radio.hungrySelector(), @options)
    for oldElement in hungries
      selector = up.fragment.toTarget(oldElement)
      if newElement = @responseDoc.select(selector)
        transition = e.booleanOrStringAttr(oldElement, 'transition')
        @steps.push({ selector, oldElement, newElement, transition, placement: 'swap' })

  containedByRivalStep: (steps, candidateStep) ->
    return u.some steps, (rivalStep) ->
      rivalStep != candidateStep &&
        rivalStep.placement == 'swap' &&
        rivalStep.oldElement.contains(candidateStep.oldElement)

  resolveOldNesting: ->
    compressed = u.uniqBy(@steps, 'oldElement')
    compressed = u.reject compressed, (step) => @containedByRivalStep(compressed, step)
    @steps = compressed

  setScrollAndFocusOptions: ->
    @steps.forEach (step, i) =>
      # Since up.motion will call @handleScrollAndFocus() after each fragment,
      # make sure that we only touch the scroll position once, for the first step.
      if i > 0
        u.assign step,
          focus: false
          reveal: false
          resetScroll: false
          restoreScroll: false

      # Store the focused element's selector, scroll position and selection range in an up.FocusCapsule
      # for later restoration.
      #
      # Note that unlike the other scroll-related options, we might need to keep in a fragment that
      # is not the first step. However, only a single step can include the focused element, or none.
      if step.placement == 'swap'
        @focusCapsule ?= up.FocusCapsule.preserveWithin(step.oldElement)

  handleFocus: (element, step) ->
    fragmentFocus = new up.FragmentFocus(
      target: element,
      layer: @layer,
      focusCapsule: @focusCapsule,
      autoMeans: ['keep', 'autofocus'],
    )
    fragmentFocus.process(step.focus)

  handleScroll: (element, options) ->
    # Copy options since we will modify the object below.
    options = u.options(options)

    # We process one of multiple scroll-changing options.
    hashOpt = options.hash
    revealOpt = options.reveal
    resetScrollOpt = options.resetScroll
    restoreScrollOpt = options.restoreScroll

    if options.placement == 'swap'
      # If we're scrolling a swapped fragment, don't animate.
      # If we're scrolling a prepended/appended fragment we allow the user to
      # pass { scrollBehavior: 'smooth' }.
      options.scrollBehavior = 'auto'

    if resetScrollOpt
      # If the user has passed { resetScroll: false } we scroll to the top all
      # viewports that are either containing or are contained by element.
      return up.viewport.resetScroll(u.merge(options, around: element))
    else if restoreScrollOpt
      # If the user has passed { restoreScroll } we restore the last known scroll
      # positions for the new URL, for all viewports that are either containing or
      # are contained by element.
      return up.viewport.restoreScroll(u.merge(options, around: element))
    else if hashOpt && revealOpt == true
      # If a { hash } is given, we will reveal the element it refers to.
      # This can be disabled with { reveal: false }.
      return up.viewport.revealHash(hashOpt, options)

    else if revealOpt
      # We allow to pass another element as { reveal } option
      if u.isElementish(revealOpt)
        element = e.get(revealOpt) # unwrap jQuery
      # If the user has passed a CSS selector as { reveal } option, we try to find
      # and reveal a matching element in the layer that we're updating.
      else if u.isString(revealOpt)
        element = up.fragment.get(revealOpt, options)
      else
        # We reveal the given `element` argument.

      # If selectorOrElement was a CSS selector, don't blow up by calling reveal()
      # with an empty jQuery collection. This might happen if a failed form submission
      # reveals the first validation error message, but the error is shown in an
      # unexpected element.
      if element
        return up.reveal(element, options)

    # If we didn't need to scroll above, just return a resolved promise
    # to fulfill this function's signature.
    return Promise.resolve()
