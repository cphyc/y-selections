


class YSelections
  constructor: ()->

  _name: "Selections"

  _getModel: (Y, Operation) ->
    if not @_model?
      @_model = new Operation.Composition(@, []).execute()
    @_model

  _setModel: (@_model)->

  _apply: (delta)->
    undos = [] # list of deltas that are necessary to undo the change
    from = @_model.HB.getOperation delta.from
    to = @_model.HB.getOperation delta.to
    createSelection = (from, to, attrs)->
      new_attrs = {}
      for n,v of attrs
        new_attrs[n] = v
      {
        from: from
        to: to
        attrs: new_attrs
      }

    extendSelection = (selection)->
      if delta.type is "unselect"
        undo_attrs = {}
        for n in delta.attrs
          if selection.attrs[n]?
            undo_attrs[n] = selection.attrs[n]
          delete selection.attrs[n]
        undos.push
          from: delta.from
          to: delta.to
          attrs: undo_attrs
          type: "select"
      else
        undo_attrs = {} # for undo selection (overwrite of existing selection)
        undo_attrs_list = [] # for undo selection (not overwrite)
        undo_need_unselect = false
        undo_need_select = false
        for n,v of delta.attrs
          if selection.attrs[n]?
            undo_attrs[n] = selection.attrs[n]
            undo_need_select = true
          else
            undo_attrs_list.push n
            undo_need_unselect = true
          selection.attrs[n] = v
        if undo_need_select
          undos.push
            from: delta.from
            to: delta.to
            attrs: undo_attrs
            type: "select"
        if undo_need_unselect
          undos.push
            from: delta.from
            to: delta.to
            attrs: undo_attrs_list
            type: "unselect"

    if not (from? and to?)
      console.log "wasn't able to apply the selection.."
    # Algorithm overview:
    # 1. cut off the selection that intersects with from
    # 2. cut off the selection that intersects with to
    # 3. extend / add selections inbetween

    #
    #### 1. cut off the selection that intersects with from
    #
    cut_off_from = ()->
      # check if a selection (to the left of $from) intersects with $from
      if from.selection? and from.selection.from is from
        # does not intersect, because the start is already selected
        return
      # find first selection to the left
      o = from.prev_cl
      while (not o.selection?) and (o.type isnt "Delimiter")
        o = o.prev_cl
      if (not o.selection?) or o.selection.to is o
        # no intersection
        return
      # We found a selection that intersects with $from.
      # Now we have to check if it also intersects with $to.
      # Then we cut it in such a way,
      # that the selection does not intersect with $from and $to anymore.

      # this is a reference for the selections that are created/modified:
      # old_selection is outer (not between $from $to)
      #   - will be changed in such a way that it is to the left of $from
      # new_selection is inner (inbetween $from $to)
      #   - created, right after $from
      # opt_selection is outer (after $to)
      #   - created (if necessary), right after $to
      old_selection = o.selection

      # check if found selection also intersects with $to
      # * starting from $from, go to the right until you found either $to or old_selection.to
      # ** if $to: no intersection with $to
      # ** if $old_selection.to: intersection with $to!
      o = from
      while (o isnt old_selection.to) and (o isnt to)
        o = o.next_cl

      if o is old_selection.to
        # no intersection with to!
        # create $new_selection
        new_selection = createSelection from, old_selection.to, old_selection.attrs

        # update references
        old_selection.to = from.prev_cl
        # update references (pointers to respective selections)
        old_selection.to.selection = old_selection

        new_selection.from.selection = new_selection
        new_selection.to.selection = new_selection
      else
        # there is an intersection with to!

        # create $new_selection
        new_selection = createSelection from, to, old_selection.attrs

        # create $opt_selection
        opt_selection = createSelection to.next_cl, old_selection.to, old_selection.attrs

        # update references
        old_selection.to = from.prev_cl
        # update references (pointers to respective selections)
        old_selection.to.selection = old_selection

        opt_selection.from.selection = opt_selection
        opt_selection.to.selection = opt_selection

        new_selection.from.selection = new_selection
        new_selection.to.selection = new_selection


    cut_off_from()

    # 2. cut off the selection that intersects with $to
    cut_off_to = ()->
      # check if a selection (to the left of $to) intersects with $to
      if to.selection? and to.selection.to is to
        # does not intersect, because the end is already selected
        return
      # find first selection to the left
      o = to
      while (not o.selection?) and (o isnt from)
        o = o.prev_cl
      if (not o.selection?) or o.selection["to"] is o
        # no intersection
        return
      # We found a selection that intersects with $to.
      # Now we have to cut it in such a way,
      # that the selection does not intersect with $to anymore.

      # this is a reference for the selections that are created/modified:
      # it is similar to the one above, except that we do not need opt_selection anymore!
      # old_selection is inner (between $from and $to)
      #   - will be changed in such a way that it is to the left of $to
      # new_selection is outer ( outer $from and $to)
      #   - created, right after $to

      old_selection = o.selection

      # create $new_selection
      new_selection = createSelection to.next_cl, old_selection.to, old_selection.attrs

      # update references
      old_selection.to = to
      # update references (pointers to respective selections)
      old_selection.to.selection = old_selection

      new_selection.from.selection = new_selection
      new_selection.to.selection = new_selection

    cut_off_to()

    # 3. extend / add selections in between
    o = from
    while (o isnt to.next_cl)
      if o.selection?
        console.log "1"
        # just extend the existing selection
        extendSelection o.selection, delta # will push undo-deltas to $undos
        o = o.selection.to.next_cl
      else
        # create a new selection (until you find the next one)
        console.log "2"
        start = o
        while (not o.next_cl.selection?) and (o isnt to)
          o = o.next_cl
        end = o
        if delta.type isnt "unselect"
          attr_list = []
          for n,v of delta.attrs
            attr_list.push n
          undos.push
            from: start.getUid()
            to: end.getUid()
            attrs: attr_list
            type: "unselect"
          selection = createSelection start, end, delta.attrs
          start.selection = selection
          end.selection = selection
        o = o.next_cl

    return delta # it is necessary that delta is returned in the way it was applied on the global delta.
    # so that yjs can know exactly what was applied.

  # "undo" a delta from the composition_value
  _unapply: (deltas)->
    # _apply returns a _list_ of deltas, that are neccessary to undo the change. Now we _apply every delta in the list (and discard the results)
    for delta in deltas
      @_apply delta
    return

  # update the globalDelta with delta


  # select _from_, _to_ with an _attribute_
  select: (from, to, attrs)->
    delta = # probably not as easy as this
      from: from.getUid()
      to: to.getUid()
      attrs: attrs
      type: "select"

    @_model.applyDelta(delta)

  # unselect _from_, _to_ with an _attribute_
  unselect: (from, to, attrs)->
    if typeof attrs is "string"
      attrs = [attrs]
    if attrs.constructor isnt Array
      throw new Error "Y.Selections.prototype.unselect expects an Array or String as the third parameter (attributes)!"
    delta = # probably not as easy as this
      from: from.getUid()
      to: to.getUid()
      attrs: attrs
      type: "unselect"

    @_model.applyDelta(delta)

  # * get all the selections of a y-list
  # * this will also test if the selections are well formed (after $from follows $to follows $from ..)
  getSelections: (list)->
    o = list.ref(0)
    sel_start = null
    pos = 0
    result = []

    while o.next_cl?
      if o.selection?
        if o.selection.from is o
          if sel_start?
            throw new Error "Found two consecutive from elements. The selections are no longer safe to use! (contact the owner of the repository)"
          else
            sel_start = pos
        if o.selection.to is o
          if sel_start?
            number_of_attrs = 0
            attrs = {}
            for n,v of o.selection.attrs
              attrs[n] = v
              number_of_attrs++
            if number_of_attrs > 0
              result.push
                from: sel_start
                to: pos
                attrs: attrs
            sel_start = null
          else
            throw new Error "Found two consecutive to elements. The selections are no longer safe to use! (contact the owner of the repository)"
        else if o.selection.from isnt o
          throw new Error "This reference should not point to this selection, because the selection does not point to the reference. The selections are no longer safe to use! (contact the owner of the repository)"
      pos++
      o = o.next_cl
    return result

  observe: (f)->
    @_model.observe f


if window?
  if window.Y?
    window.Y.Selections = YSelections
  else
    throw new Error "You must first import Y!"

if module?
  module.exports = YSelections



