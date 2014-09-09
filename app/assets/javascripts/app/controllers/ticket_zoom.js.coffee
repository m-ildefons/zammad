class App.TicketZoom extends App.Controller
  constructor: (params) ->
    super

    # check authentication
    return if !@authenticate()

    @navupdate '#'

    @form_meta      = undefined
    @ticket_id      = params.ticket_id
    @article_id     = params.article_id
    @signature      = undefined

    @key = 'ticket::' + @ticket_id
    cache = App.Store.get( @key )
    if cache
      @load(cache)
    update = =>
      @fetch( @ticket_id, false )
    @interval( update, 450000, 'pull_check' )

    # fetch new data if triggered
    @bind(
      'Ticket:update'
      (data) =>
        update = =>
          if data.id.toString() is @ticket_id.toString()
            @log 'notice', 'TRY', new Date(data.updated_at), new Date(@ticketUpdatedAtLastCall)
            if !@ticketUpdatedAtLastCall || ( new Date(data.updated_at).toString() isnt new Date(@ticketUpdatedAtLastCall).toString() )
              @fetch( @ticket_id, false )
        @delay( update, 1800, 'ticket-zoom-' + @ticket_id )
    )

  meta: =>
    meta =
      url: @url()
      id:  @ticket_id
    if @ticket
      @ticket = App.Ticket.fullLocal( @ticket.id )
      meta.head  = @ticket.title
      meta.title = '#' + @ticket.number + ' - ' + @ticket.title
    meta

  url: =>
    '#ticket/zoom/' + @ticket_id

  activate: =>
    @navupdate '#'

  changed: =>
    formCurrent = @formParam( @el.find('.ticket-update') )
    diff = difference( @formDefault, formCurrent )
    return false if !diff || _.isEmpty( diff )
    return true

  release: =>
    # nothing

  fetch: (ticket_id, force) ->

    return if !@Session.all()

    # get data
    @ajax(
      id:    'ticket_zoom_' + ticket_id
      type:  'GET'
      url:   @apiPath + '/ticket_full/' + ticket_id
      processData: true
      success: (data, status, xhr) =>

        # check if ticket has changed
        newTicketRaw = data.assets.Ticket[ticket_id]
        if @ticketUpdatedAtLastCall && !force

          # return if ticket hasnt changed
          return if @ticketUpdatedAtLastCall is newTicketRaw.updated_at

          # notify if ticket changed not by my self
          if newTicketRaw.updated_by_id isnt @Session.all().id
            App.TaskManager.notify( @task_key )

          # rerender edit box
          @editDone = false

        # remember current data
        @ticketUpdatedAtLastCall = newTicketRaw.updated_at

        @load(data, force)
        App.Store.write( @key, data )

      error: (xhr, status, error) =>

        # do not close window if request is aborted
        return if status is 'abort'

        # do not close window on network error but if object is not found
        return if status is 'error' && error isnt 'Not Found'

        # remove task
        App.TaskManager.remove( @task_key )
    )

    if !@doNotLog
      @doNotLog = 1
      @recentView( 'Ticket', ticket_id )

  load: (data, force) =>

    # remember article ids
    @ticket_article_ids = data.ticket_article_ids

    # get edit form attributes
    @form_meta = data.form_meta

    # get signature
    @signature = data.signature

    # load assets
    App.Collection.loadAssets( data.assets )

    # get data
    @ticket = App.Ticket.fullLocal( @ticket_id )

    # render page
    @render(force)

  render: (force) =>

    # update taskbar with new meta data
    App.Event.trigger 'task:render'
    if !@renderDone
      @renderDone = true
      @html App.view('ticket_zoom')(
        ticket:     @ticket
        nav:        @nav
        isCustomer: @isRole('Customer')
      )
      @TicketTitle()
      @Widgets()

    @TicketAction()
    @ArticleView()

    if force || !@editDone
      # reset form on force reload
      if force && _.isEmpty( App.TaskManager.get(@task_key).state )
        App.TaskManager.update( @task_key, { 'state': {} })
      @editDone = true

      # rerender widget if it hasn't changed
      if !@editWidget || _.isEmpty( App.TaskManager.get(@task_key).state )
        @editWidget = @Edit()

    # scroll to article if given
    if @article_id && document.getElementById( 'article-' + @article_id )
      offset = document.getElementById( 'article-' + @article_id ).offsetTop
      offset = offset - 45
      scrollTo = ->
        @scrollTo( 0, offset )
      @delay( scrollTo, 100, false )

  TicketTitle: =>
    # show ticket title
    new TicketTitle(
      ticket: @ticket
      el:     @el.find('.ticket-title')
    )

  ArticleView: =>
    # show article
    new ArticleView(
      ticket:             @ticket
      ticket_article_ids: @ticket_article_ids
      el:                 @el.find('.article-view')
      ui:                 @
    )

  Edit: =>
    # show edit
    new Edit(
      ticket:     @ticket
      el:         @el.find('.edit')
      form_meta:  @form_meta
      task_key:   @task_key
      ui:         @
    )

  Widgets: =>
    # show ticket action row
    new Widgets(
      ticket:     @ticket
      task_key:   @task_key
      el:         @el.find('.widgets')
      ui:         @
    )

  TicketAction: =>
    # start action controller
    if !@isRole('Customer')
      new ActionRow(
        el:      @el.find('.action')
        ticket:  @ticket
        ui:      @
      )

class TicketTitle extends App.Controller
  events:
    'blur .ticket-title-update': 'update'

  constructor: ->
    super

    @ticket      = App.Ticket.fullLocal( @ticket.id )
    @subscribeId = @ticket.subscribe(@render)
    @render(@ticket)

  render: (ticket) =>
    @html App.view('ticket_zoom/title')(
      ticket: ticket
    )

  update: (e) =>
    $this = $(e.target)
    title = $this.html()
    title = ('' + title)
      .replace(/<.+?>/g, '')
    title = ('' + title)
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
    if title is '-'
      title = ''

    # update title
    @ticket.title = title
    @ticket.save()

    # update taskbar with new meta data
    App.Event.trigger 'task:render'

  release: =>
    App.Ticket.unsubscribe( @subscribeId )

class TicketInfo extends App.ControllerDrox
  constructor: ->
    super

    @subscribeId = @ticket.subscribe(@render)
    @render(@ticket)

  render: (ticket) =>
    @html @template(
      file:   'ticket_zoom/info'
      header: '#' + ticket.number
      params:
        ticket: ticket
    )

    # start tag controller
    if !@isRole('Customer')
      new App.WidgetTag(
        el:           @el.find('.tag_info')
        object_type:  'Ticket'
        object:        ticket
      )

  release: =>
    App.Ticket.unsubscribe( @subscribeId )

class Widgets extends App.Controller
  constructor: ->
    super
    @subscribeId = @ticket.subscribe(@render)
    @render(@ticket)

  render: (ticket) =>

    @html App.view('ticket_zoom/widgets')()

    # show ticket info
    new TicketInfo(
      ticket:  ticket
      el:      @el.find('.ticket_info')
    )

    # start customer info controller
    if !@isRole('Customer')
      new App.WidgetUser(
        el:      @el.find('.customer_info')
        user_id: ticket.customer_id
        ticket:  ticket
      )

    # start link info controller
    if !@isRole('Customer')
      new App.WidgetLink(
        el:           @el.find('.link_info')
        object_type:  'Ticket'
        object:       ticket
      )

    # show frontend times
    @frontendTimeUpdate()

  release: =>
    App.Ticket.unsubscribe( @subscribeId )

class Edit extends App.Controller
  events:
    'click .submit':             'update'
    'click [data-type="reset"]': 'reset'

  constructor: ->
    super
    @render()

  release: =>
    @autosaveStop()
    if @subscribeIdTextModule
      App.Ticket.unsubscribe(@subscribeIdTextModule)

  render: ->

    ticket = App.Ticket.fullLocal( @ticket.id )

    @html App.view('ticket_zoom/edit')(
      ticket:     ticket
      isCustomer: @isRole('Customer')
      formChanged: !_.isEmpty( App.TaskManager.get(@task_key).state )
    )

    @form_id = App.ControllerForm.formId()
    defaults = ticket.attributes()
    if @isRole('Customer')
      delete defaults['state_id']
      delete defaults['state']
    if !_.isEmpty( App.TaskManager.get(@task_key).state )
      defaults = App.TaskManager.get(@task_key).state
    formChanges = (params, attribute, attributes, classname, form, ui) =>
      if @form_meta.dependencies && @form_meta.dependencies[attribute.name]
        dependency = @form_meta.dependencies[attribute.name][ parseInt(params[attribute.name]) ]
        if dependency

          for fieldNameToChange of dependency
            filter = []
            if dependency[fieldNameToChange]
              filter = dependency[fieldNameToChange]

            # find element to replace
            for item in attributes
              if item.name is fieldNameToChange
                item.display = false
                item['filter'] = {}
                item['filter'][ fieldNameToChange ] = filter
                item.default = params[item.name]
                #if !item.default
                #  delete item['default']
                newElement = ui.formGenItem( item, classname, form )

            # replace new option list
            form.find('[name="' + fieldNameToChange + '"]').replaceWith( newElement )

    new App.ControllerForm(
      el:       @el.find('.form-ticket-update')
      form_id:  @form_id
      model:    App.Ticket
      screen:   'edit'
      handlers: [
        formChanges
      ]
      filter:    @form_meta.filter
      params:    defaults
    )
    new App.ControllerForm(
      el:        @el.find('.form-article-update')
      form_id:   @form_id
      model:     App.TicketArticle
      screen:   'edit'
      filter:
        type_id: [1,9,5]
      params:    defaults
      dependency: [
        {
          bind: {
            name:     'type_id'
            relation: 'TicketArticleType'
            value:    ['email']
          },
          change: {
            action: 'show'
            name: ['to', 'cc'],
          },
        },
        {
          bind: {
            name:     'type_id'
            relation: 'TicketArticleType'
            value:    ['note', 'phone', 'twitter status']
          },
          change: {
            action: 'hide'
            name: ['to', 'cc'],
          },
        },
        {
          bind: {
            name:     'type_id'
            relation: 'TicketArticleType'
            value:    ['twitter direct-message']
          },
          change: {
            action: 'show'
            name: ['to'],
          },
        },
      ]
    )

    # remember form defaults
    @ui.formDefault = @formParam( @el.find('.ticket-update') )

    # start auto save
    @autosaveStart()

    # enable user popups
    @userPopups()

    # show text module UI
    if !@isRole('Customer')
      textModule = new App.WidgetTextModule(
        el:   @el.find('textarea')
        data:
          ticket: ticket
      )
      callback = (ticket) =>
        textModule.reload(
          ticket: ticket
        )
      @subscribeIdTextModule = ticket.subscribe( callback )

  autosaveStop: =>
    @clearInterval( 'autosave' )

  autosaveStart: =>
    @autosaveLast = _.clone( @ui.formDefault )
    update = =>
      currentData = @formParam( @el.find('.ticket-update') )
      diff = difference( @autosaveLast, currentData )
      if !@autosaveLast || ( diff && !_.isEmpty( diff ) )
        @autosaveLast = currentData
        @log 'notice', 'form hash changed', diff, currentData
        @el.find('.ticket-edit').addClass('form-changed')
        @el.find('.ticket-edit').find('.reset-message').show()
        @el.find('.ticket-edit').find('.reset-message').removeClass('hide')
        App.TaskManager.update( @task_key, { 'state': currentData })
    @interval( update, 3000, 'autosave' )

  update: (e) =>
    e.preventDefault()
    @autosaveStop()
    params = @formParam(e.target)

    # get ticket
    ticket = App.Ticket.fullLocal( @ticket.id )

    @log 'notice', 'update', params, ticket

    # update local ticket

    # create local article


    # find sender_id
    if @isRole('Customer')
      sender            = App.TicketArticleSender.findByAttribute( 'name', 'Customer' )
      type              = App.TicketArticleType.findByAttribute( 'name', 'web' )
      params.type_id    = type.id
      params.sender_id  = sender.id
    else
      sender            = App.TicketArticleSender.findByAttribute( 'name', 'Agent' )
      type              = App.TicketArticleType.find( params['type_id'] )
      params.sender_id  = sender.id

    # update ticket
    for key, value of params
      ticket[key] = value

    # check owner assignment
    if !@isRole('Customer')
      if !ticket['owner_id']
        ticket['owner_id'] = 1

    # check if title exists
    if !ticket['title']
      alert( App.i18n.translateContent('Title needed') )
      return

    # validate email params
    if type.name is 'email'

      # check if recipient exists
      if !params['to'] && !params['cc']
        alert( App.i18n.translateContent('Need recipient in "To" or "Cc".') )
        return

      # check if message exists
      if !params['body']
        alert( App.i18n.translateContent('Text needed') )
        return

    # check attachment
    if params['body']
      attachmentTranslated = App.i18n.translateContent('Attachment')
      attachmentTranslatedRegExp = new RegExp( attachmentTranslated, 'i' )
      if params['body'].match(/attachment/i) || params['body'].match( attachmentTranslatedRegExp )
        if !confirm( App.i18n.translateContent('You use attachment in text but no attachment is attached. Do you want to continue?') )
          @autosaveStart()
          return

    # submit ticket & article
    @log 'notice', 'update ticket', ticket

    # disable form
    @formDisable(e)

    # validate ticket
    errors = ticket.validate(
      screen: 'edit'
    )
    if errors
      @log 'error', 'update', errors

      @log 'error', errors
      @formValidate(
        form:   e.target
        errors: errors
        screen: 'edit'
      )
      @formEnable(e)
      @autosaveStart()
      return

    # validate article
    articleAttributes = App.TicketArticle.attributesGet( 'edit' )
    if params['body'] || ( articleAttributes['body'] && articleAttributes['body']['null'] is false )
      article = new App.TicketArticle
      params.from      = @Session.get( 'firstname' ) + ' ' + @Session.get( 'lastname' )
      params.ticket_id = ticket.id
      params.form_id   = @form_id

      if !params['internal']
        params['internal'] = false

      @log 'notice', 'update article', params, sender
      article.load(params)
      errors = article.validate()
      if errors
        @log 'error', 'update article', errors
        @formValidate(
          form:   e.target
          errors: errors
          screen: 'edit'
        )
        @formEnable(e)
        @autosaveStart()
        return

    ticket.save(
      done: (r) =>

        # reset form after save
        if article
          article.save(
            done: (r) =>
              @ui.fetch( ticket.id, true )

              # reset form after save
              App.TaskManager.update( @task_key, { 'state': {} })
            fail: (r) =>
              @log 'error', 'update article', r
          )
        else

          # reset form after save
          App.TaskManager.update( @task_key, { 'state': {} })

          @ui.fetch( ticket.id, true )
    )

  reset: (e) =>
    e.preventDefault()
    App.TaskManager.update( @task_key, { 'state': {} })
    @render()


class ArticleView extends App.Controller
  events:
    'click [data-type=public]':     'public_internal'
    'click [data-type=internal]':   'public_internal'
    'click .show_toogle':           'show_toogle'
    'click [data-type=reply]':      'reply'
#    'click [data-type=reply-all]':  'replyall'

  constructor: ->
    super
    @render()

  render: ->

    # get all articles
    @articles = []
    for article_id in @ticket_article_ids
      article = App.TicketArticle.fullLocal( article_id )
      @articles.push article

    # rework articles
    for article in @articles
      new Article( article: article )

    @html App.view('ticket_zoom/article_view')(
      ticket:     @ticket
      articles:   @articles
      isCustomer: @isRole('Customer')
    )

    # show frontend times
    @frontendTimeUpdate()

    # enable user popups
    @userPopups()

  public_internal: (e) ->
    e.preventDefault()
    article_id = $(e.target).parents('[data-id]').data('id')

    # storage update
    article = App.TicketArticle.find(article_id)
    internal = true
    if article.internal == true
      internal = false
    article.updateAttributes(
      internal: internal
    )

    # runtime update
    for article in @articles
      if article_id is article.id
        article['internal'] = internal

    @render()

  show_toogle: (e) ->
    e.preventDefault()
    #$(e.target).hide()
    if $(e.target).next('div')[0]
      if $(e.target).next('div').hasClass('hide')
        $(e.target).next('div').removeClass('hide')
        $(e.target).text( App.i18n.translateContent('Fold in') )
      else
        $(e.target).text( App.i18n.translateContent('See more') )
        $(e.target).next('div').addClass('hide')

  checkIfSignatureIsNeeded: (type) =>

    # add signature
    if @ui.signature && @ui.signature.body && type.name is 'email'
      body   = @ui.el.find('[name="body"]').val() || ''
      regexp = new RegExp( escapeRegExp( @ui.signature.body ) , 'i')
      if !body.match(regexp)
        body = body + "\n" + @ui.signature.body
        @ui.el.find('[name="body"]').val( body )

        # update textarea size
        @ui.el.find('[name="body"]').trigger('change')

  reply: (e) =>
    e.preventDefault()
    article_id   = $(e.target).parents('[data-id]').data('id')
    article      = App.TicketArticle.find( article_id )
    type         = App.TicketArticleType.find( article.type_id )
    customer     = App.User.find( article.created_by_id )

    # update form
    @checkIfSignatureIsNeeded(type)

    # preselect article type
    @ui.el.find('[name="type_id"]').find('option:selected').removeAttr('selected')
    @ui.el.find('[name="type_id"]').find('[value="' + type.id + '"]').attr('selected',true)
    @ui.el.find('[name="type_id"]').trigger('change')

    # empty form
    #@ui.el.find('[name="to"]').val('')
    #@ui.el.find('[name="cc"]').val('')
    #@ui.el.find('[name="subject"]').val('')
    @ui.el.find('[name="in_reply_to"]').val('')

    if article.message_id
      @ui.el.find('[name="in_reply_to"]').val(article.message_id)

    if type.name is 'twitter status'

      # set to in body
      to = customer.accounts['twitter'].username || customer.accounts['twitter'].uid
      @ui.el.find('[name="body"]').val('@' + to)

    else if type.name is 'twitter direct-message'

      # show to
      to = customer.accounts['twitter'].username || customer.accounts['twitter'].uid
      @ui.el.find('[name="to"]').val(to)

    else if type.name is 'email'
      @ui.el.find('[name="to"]').val(article.from)

    # add quoted text if needed
    selectedText = App.ClipBoard.getSelected()
    if selectedText
      body = @ui.el.find('[name="body"]').val() || ''
      selectedText = selectedText.replace /^(.*)$/mg, (match) =>
        '> ' + match
      body = selectedText + "\n" + body
      @ui.el.find('[name="body"]').val(body)

      # update textarea size
      @ui.el.find('[name="body"]').trigger('change')

class Article extends App.Controller
  constructor: ->
    super

    # define actions
    @actionRow()

    # check attachments
    @attachments()

    # html rework
    @preview()

  preview: ->

    # build html body
    # cleanup body
#    @article['html'] = @article.body.trim()
    @article['html'] = $.trim( @article.body )
    @article['html'].replace( /\n\r/g, "\n" )
    @article['html'].replace( /\n\n\n/g, "\n\n" )

    # if body has more then x lines / else search for signature
    preview       = 10
    preview_mode  = false
    article_lines = @article['html'].split(/\n/)
    if article_lines.length > preview
      preview_mode = true
      if article_lines[preview] is ''
        article_lines.splice( preview, 0, '-----SEEMORE-----' )
      else
        article_lines.splice( preview - 1, 0, '-----SEEMORE-----' )
      @article['html'] = article_lines.join("\n")
    @article['html'] = window.linkify( @article['html'] )
    notify = '<a href="#" class="show_toogle">' + App.i18n.translateContent('See more') + '</a>'

    # preview mode
    if preview_mode
      @article_changed = false
      @article['html'] = @article['html'].replace /^-----SEEMORE-----\n/m, (match) =>
        @article_changed = true
        notify + '<div class="hide preview">'
      if @article_changed
        @article['html'] = @article['html'] + '</div>'

    # hide signatures and so on
    else
      @article_changed = false
      @article['html'] = @article['html'].replace /^\n{0,10}(--|__)/m, (match) =>
        @article_changed = true
        notify + '<div class="hide preview">' + match
      if @article_changed
        @article['html'] = @article['html'] + '</div>'

  actionRow: ->
    if @isRole('Customer')
      @article.actions = []
      return

    actions = []
    if @article.internal is true
      actions = [
        {
          name: 'set to public'
          type: 'public'
        }
      ]
    else
      actions = [
        {
          name: 'set to internal'
          type: 'internal'
        }
      ]
    if @article.type.name is 'note'
#        actions.push []
    else
      if @article.sender.name is 'Customer'
        actions.push {
          name: 'reply'
          type: 'reply'
          href: '#'
        }
#        actions.push {
#          name: 'reply all'
#          type: 'reply-all'
#          href: '#'
#        }
        actions.push {
          name: 'split'
          type: 'split'
          href: '#ticket_create/call_inbound/' + @article.ticket_id + '/' + @article.id
        }
    @article.actions = actions

  attachments: ->
    if @article.attachments
      for attachment in @article.attachments
        attachment.size = @humanFileSize(attachment.size)

class ActionRow extends App.Controller
  events:
    'click [data-type=history]':  'history_dialog'
    'click [data-type=merge]':    'merge_dialog'
    'click [data-type=customer]': 'customer_dialog'

  constructor: ->
    super
    @render()

  render: ->
    @html App.view('ticket_zoom/actions')()

  history_dialog: (e) ->
    e.preventDefault()
    new App.TicketHistory( ticket: @ticket )

  merge_dialog: (e) ->
    e.preventDefault()
    new App.TicketMerge( ticket: @ticket, task_key: @ui.task_key )

  customer_dialog: (e) ->
    e.preventDefault()
    new App.TicketCustomer( ticket: @ticket )

class TicketZoomRouter extends App.ControllerPermanent
  constructor: (params) ->
    super

    # cleanup params
    clean_params =
      ticket_id:  params.ticket_id
      article_id: params.article_id
      nav:        params.nav

    App.TaskManager.add( 'Ticket-' + @ticket_id, 'TicketZoom', clean_params )

App.Config.set( 'ticket/zoom/:ticket_id', TicketZoomRouter, 'Routes' )
App.Config.set( 'ticket/zoom/:ticket_id/nav/:nav', TicketZoomRouter, 'Routes' )
App.Config.set( 'ticket/zoom/:ticket_id/:article_id', TicketZoomRouter, 'Routes' )
