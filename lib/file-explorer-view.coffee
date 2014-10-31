path = require 'path'
fs = require 'fs'
shell = require 'shell'
{Minimatch} = require 'minimatch'
{$$, SelectListView} = require 'atom'

module.exports =
class FileExplorerView extends SelectListView
  @selectedDirectoryPath: null
  
  initialize: ->
    super
    @addClass('overlay from-top file-explorer-view')
        
    @subscribe this, 'pane:split-left', =>
      @splitOpenPath (pane, session) -> pane.splitLeft(session)
    @subscribe this, 'pane:split-right', =>
      @splitOpenPath (pane, session) -> pane.splitRight(session)
    @subscribe this, 'pane:split-down', =>
      @splitOpenPath (pane, session) -> pane.splitDown(session)
    @subscribe this, 'pane:split-up', =>
      @splitOpenPath (pane, session) -> pane.splitUp(session)
    
  destroy: ->
    @cancel()
    @remove()
    
  getFilterKey: ->
    'fileName'
  
  viewForItem: ({filePath, parent}) ->
    stat = fs.statSync(filePath)
    $$ ->
      @li class: 'two-lines', =>
        if parent?
          @div "..", class: "primary-line file icon icon-file-directory"
        else if stat.isDirectory()
          @div path.basename(filePath), class: "primary-line file icon icon-file-directory"
          @div atom.project.relativize(filePath), class: 'secondary-line path no-icon'
        else 
          @div path.basename(filePath), class: "primary-line file icon icon-file-text"
          @div atom.project.relativize(filePath), class: 'secondary-line path no-icon'
  
  confirmed: ({filePath, parent}) ->
    stat = fs.statSync(filePath)
    if stat.isFile()
      atom.workspaceView.open filePath
    else if stat.isDirectory()
      @openDirectory(filePath)
      
  goParent: ->
    if @selectedDirectoryPath is atom.project.getRootDirectory().getRealPathSync() 
      atom.beep()
    else
      @openDirectory(path.dirname(@selectedDirectoryPath))
  
  moveToTrash: ->
    item = @getSelectedItem()
    selectedDirectoryPath = @selectedDirectoryPath

    atom.confirm
      message: "Are you sure you want to delete the selected item?"
      detailedMessage: "You are deleting: #{item.fileName}"
      buttons:
        "Move to Trash": ->
          shell.moveItemToTrash(item.filePath)
          @openDirectory(selectedDirectoryPath)
        "Cancel": null


  toggleHomeDirectory: ->
    @toggle(atom.project.getRootDirectory().getRealPathSync())
    
  toggleCurrentDirectory: ->
    activeEditor = atom.workspace.getActiveEditor()
    projectPath = atom.project.getRootDirectory().getRealPathSync()

    if activeEditor?.getPath()? and activeEditor.getPath().indexOf(projectPath) isnt -1
      @toggle(path.dirname(activeEditor.getPath()))
    else
      atom.beep()
    
  toggle: (targetDirectory) ->
    if !targetDirectory?
      return atom.beep()

    if @hasParent()
      @setItems []
      @cancel()
    else
      @populate(targetDirectory)
      @attach()
      
  attach: ->
    @storeFocusedElement()
    atom.workspaceView.append(this)
    @focusFilterEditor()
    
  populate: (targetDirectoryPath) ->
    @selectedDirectoryPath = targetDirectoryPath
    displayFiles = []
                           
    unless @isProjectRoot(targetDirectoryPath)
      displayFiles.push {filePath: path.dirname(targetDirectoryPath), fileName: file, parent: true}
    
    for file in fs.readdirSync(targetDirectoryPath)
      fileFullPath = path.join(targetDirectoryPath, file)
      continue if @matchIgnores(file)
      displayFiles.push {filePath: fileFullPath, fileName: file}
          
    @setItems displayFiles
      
  openDirectory: (targetDirectory) ->
    @cancel()
    @toggle(targetDirectory)

  splitOpenPath: (fn) ->
    filePath = @getSelectedItem() ? {}
    return unless filePath

    if pane = atom.workspaceView.getActivePane()
      atom.project.open(filePath).done (editor) =>
        fn(pane, editor)
    else
      atom.workspaceView.open filePath

  isProjectRoot: (selectedDirectoryPath) ->
    if selectedDirectoryPath.split(path.sep).length > atom.project.getRootDirectory().getRealPathSync().split(path.sep).length
      return false
    else
      return true
    
  matchIgnores: (fileName) ->
    activeEditor = atom.workspace.getActiveEditor()
    if activeEditor?.getPath()?
      currentFileName = path.basename(activeEditor.getPath())
      return true if fileName is currentFileName and atom.config.get("file-explorer.excludeActiveFile") is true
    
    ignoredNames = for ignores in atom.config.get("file-explorer.ignoredNames")
      new Minimatch(ignores, matchBase: true, dot: true) 
      
    for ignoredName in ignoredNames
      return true if ignoredName.match(fileName)
