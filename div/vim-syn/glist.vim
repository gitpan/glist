" Vim Syntax File
" Language:	glist configuration files (glist.config)
" Maintainer:	Ask Solem Hoel <ask@unixmonks.net>
" Last change:  2001-04-11
" For glist v1.0

syn clear

syn match 	glistComment 	/^\s*#.\+/
syn match	glistComment	/^\s*\/\/.\+/
syn match	glistComment	/\/\/.\+/
syn match 	glistParameter 	/^\s*[a-zA-Z0-9_]\+/ contains=glistKeyword
syn match	glistPath	/ .*\/.*/
syn match	glistNumber 	/\d\+/
syn keyword 	glistBoolean 	true false yes no
syn match	glistOperator 	/{/
syn match	glistOperator	/}/

syn keyword	glistKeyword contained 	owner send_allow push_list_id
syn keyword	glistKeyword contained 	database server type file sender
syn keyword	glistKeyword contained 	subject_prefix admin hostname
syn keyword	glistKeyword contained 	hide_sender reply_to recipient blacklist
syn keyword	glistKeyword contained 	size_limit daemon_args header footer
syn keyword	glistKeyword contained 	hello_file bye_file request info
syn keyword	glistKeyword contained	adm_by_mail sql_query allow_attachments
syn keyword	glistKeyword contained	attachment_size_limit need_approval
syn keyword	glistKeyword contained 	moderators header_checks body_checks
syn keyword	glistKeyword contained 	allow_subscribe content_checks
syn keyword 	glistKeyword contained	require include

syn keyword	glistSection contained	list alias

if !exists("did_glist_syntax_inits")
	let did_glist_syntax_inits=1
	hi link glistComment 	Comment
	hi link glistKeyword 	Keyword
	hi link glistParameter 	Keyword
	hi link glistOperator	Constant
	hi link glistNumber	Number
	hi link glistPath	Constant
	hi link glistBoolean	Boolean
endif

let b:current_syntax = "glist"
