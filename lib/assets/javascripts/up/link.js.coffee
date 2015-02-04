###*
Links
=====

TODO: Write some docs or merge with `up.flow` docs.
  
@class up.link
###

up.link = (->

  u = up.util
  
  ###*
  Visits the given URL without a full page load.
  This is done by fetching `url` through an AJAX request
  and replacing the current `<body>` element with the response's `<body>` element.
  
  @method up.visit
  @param {String} url
    The URL to visit.
  @param {Object} options
    See options for {{#crossLink "up.flow/up.replace"}}{{/crossLink}}.
  @example
      up.visit('/users')
  ###
  visit = (url, options) ->
    console.log("up.visit", url)
    # options = util.options(options, )
    up.replace('body', url, options)

  ###*
  Follows the given link via AJAX and replaces a CSS selector in the current page
  with corresponding elements from a new page fetched from the server.
  
  @method up.follow
  @param {Element|jQuery|String} link
    An element or selector which resolves to an `<a>` tag
    or any element that is marked up with an `up-follow` attribute.
  @param {String} [options.target]
    The selector to replace.
    Defaults to the `up-target` attribute on `link`,
    or to `body` if such an attribute does not exist.
  @param {Function|String} [options.transition]
    A transition function or name.
  ###
  follow = (link, options) ->
    $link = $(link)

    options = u.options(options)
    url = u.option($link.attr('href'), $link.attr('up-follow'))
    selector = u.option(options.target, $link.attr('up-target'), 'body')
    options.transition = u.option(options.transition, $link.attr('up-transition'), $link.attr('up-animation')) 
    options.history = u.option(options.history, $link.attr('up-history'))
    
    up.replace(selector, url, options)

  resolve = (element) ->
    $element = $(element)
    if $element.is('a') || u.presentAttr($element, 'up-follow')
      $element
    else
      $element.find('a:first')

  resolveUrl = (element) ->
    if $link = resolve(element)
      u.option($link.attr('href'), $link.attr('up-follow'))
      
  ###*
  Follows this link via AJAX and replaces a CSS selector in the current page
  with corresponding elements from a new page fetched from the server.

      <a href="/users" up-target=".main">User list</a>

  @method a[up-target]
  @ujs
  @param {String} up-target
    The CSS selector to replace
  ###
  up.on 'click', 'a[up-target]', (event, $link) ->
    event.preventDefault()
    follow($link)

  ###*
  If applied on a link, Follows this link via AJAX and replaces the
  current `<body>` element with the response's `<body>` element

      <a href="/users" up-follow>User list</a>

  You can also apply `[up-follow]` to any element that contains a link
  in order to enlarge the link's click area:

      <div class="notification" up-follow>
         Record was saved!
         <a href="/records">Close</a>
      </div>

  In the example above, clicking anywhere within `.notification` element
  would follow the `Close` link.

  @method [up-follow]
  @ujs
  @param {String} [up-follow]
  ###
  up.on 'click', '[up-follow]', (event, $element) ->
    
    childLinkClicked = ->
      $target = $(event.target)
      $targetLink = $target.closest('a, [up-follow]')
      $targetLink.length && $element.find($targetLink).length
      
    unless childLinkClicked()
      event.preventDefault()
      follow(resolve($element))

  visit: visit
  follow: follow
  resolve: resolve
  resolveUrl: resolveUrl

)()

up.visit = up.link.visit
up.follow = up.link.follow
