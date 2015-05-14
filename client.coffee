Db = require 'db'
Dom = require 'dom'
Form = require 'form'
Icon = require 'icon'
Modal = require 'modal'
Obs = require 'obs'
Plugin = require 'plugin'
Page = require 'page'
Server = require 'server'
Ui = require 'ui'
{tr} = require 'i18n'

exports.render = ->
	
	req0 = Page.state.get(0)
	if req0 is 'new'
		renderEditOrNew()
		return
	if +req0 and Page.state.get(1) is 'edit'
		renderEditOrNew +req0
		return
	if +req0
		renderView +req0
		return
	
	settleO = Db.shared.ref('settle')
	if settleO.isHash()
		renderSettlePane(settleO)

	Ui.list !->
		Dom.h2 tr("Balances")
		Db.shared.iterate 'balances', (user) !->
			Ui.item !->
				Ui.avatar Plugin.userAvatar(user.key())
				Dom.div !->
					Dom.style Flex: true
					Dom.div Plugin.userName(user.key())
				Dom.div !->
					 Dom.text formatMoney(user.get())
					 
		if !settleO.isHash()
			if Plugin.userIsAdmin()
				Dom.div !->
					Dom.style textAlign: 'right'
					Ui.button tr("Initiate settle"), !->
						require('modal').confirm tr("Initiate settle?"), tr("People with negatives balance are asked to pay up. People with a positive balances should confirm their payments."), !->
							Server.call 'settleStart'
			else
				Dom.div !->
					Dom.style
						textAlign: 'center'
						margin: '4px 0'
						fontSize: '80%'
						color: '#888'
						fontStyle: 'italic'
					Dom.text tr("Want to settle balances? Ask a group admin to initiate settle mode!")
						

	Ui.list !->
		Dom.h2 tr("Latest transactions")
		Db.shared.iterate 'transactions', (tx) !->
			Ui.item !->
				Dom.div !->
					Dom.text tx.get('text')
					Dom.div !->
						Dom.style fontSize: '80%'
						byIds = (id for id of tx.get('by'))
						forIds = (id for id of tx.get('for'))					
						Dom.text tr("%1 payed %2 for %3", formatGroup(byIds, true), formatMoney(tx.get('total')), formatGroup(forIds))
				
				Dom.onTap !->
					Page.nav [tx.key()]
		, (tx) -> -tx.key()
						
	Page.setFooter
		label: tr("+ New transaction")
		action: !->
			Page.nav ['new']
			
renderView = (txId) !->
	Page.setActions
		icon: 'good2'
		tap: !->
			Page.nav [txId, 'edit']
		
	Ui.emptyText("TODO %1", txId)
	
	require('social').renderComments(txId)
			

renderEditOrNew = (editId) !->

	if editId
		edit = Db.shared.ref('transactions', editId)
		if !edit.isHash()
			Ui.emptyText tr("No such transaction")
			return
			
		log 'editing!', JSON.stringify(edit.get())

	if Db.shared.isHash('settle')
		Dom.div !->
			Dom.style
				margin: '0 0 8px'
				background: '#888'
				color: '#fff'
				fontSize: '80%'
				padding: '4px'
				fontStyle: 'italic'
			Dom.text tr("There is an ongoing settle. ")
			if editId
				Dom.text tr("Changes in transactions will not be included.")
			else
				Dom.text tr("New transactions will not be included.")
		
	totalO = Obs.create 0	
	
	Dom.section !->
		Dom.div !->
			Dom.style Box: 'middle'
			Dom.div !->
				Dom.style Flex: true
				Form.input
					name: 'text'
					value: edit.get('text') if edit
					text: tr("Description")
			Dom.div !->
				Dom.style width: '80px', margin: '0 0 0 10px'
				Form.input
					name: 'total'
					type: 'number'
					text: '0.-'
					value: edit.get('total') if edit
					onChange: (value) ->
						log 'totalO write', +value
						totalO.set +value
						
		Form.condition (values) ->
			if +values.total <= 0
				tr("Enter amount")
	
	Ui.list !->
		Dom.h2 tr("Payed by")
		dbg.by = byO = Obs.create {}
		if edit
			byO.set edit.get('by')
		else
			byO.set Plugin.userId(), true
		[handleChange] = Form.makeInput
			name: 'by'
			value: byO.peek()
		Obs.observe !->
			handleChange byO.get()
		
		sumO = Obs.create(0)
		divideO = Obs.create(0)
		byO.iterate (x) !->
			v = x.get()
			if v is true
				divideO.incr()
				Obs.onClean !-> divideO.incr(-1)
			else if v? # due to obs2 bug
				sumO.incr(v)
				Obs.onClean !-> sumO.incr(-v)
		
		byO.iterate (user) !->
			Ui.item !->
				Ui.avatar Plugin.userAvatar(user.key())
				Dom.div !->
					Dom.style Flex: true
					Dom.text Plugin.userName(user.key())
					Dom.div !->
						Dom.style fontSize: '80%'
						Dom.text tr("Tap to change")
				Dom.onTap !->
					selectUser (userId) !->
						byO.set {}
						byO.set userId, true
				
				Dom.div !->
					Dom.style fontSize: '90%'
					amount = user.get()
					if amount is true
						amount = (totalO.get() - sumO.get()) / divideO.get()
					Dom.text formatMoney(amount)
			
		false && Dom.div !->
			Dom.style
				fontSize: '90%'
				padding: '4px'
				color: Plugin.colors().highlight
			Dom.text tr("+ Add")
			Dom.onTap !->
				123


	Ui.list !->
		Dom.h2 tr("Payed for")
		forO = Obs.create {}
		if edit
			forO.set edit.get('for')
			
		[handleChange] = Form.makeInput
			name: 'for'
			value: forO.peek()
		Obs.observe !->
			handleChange forO.get()
		
		sumO = Obs.create(0)
		divideO = Obs.create(0)
		forO.iterate (x) !->
			v = x.get()
			if v is true
				divideO.incr()
				Obs.onClean !-> divideO.incr(-1)
			else if v? # due to obs2 bug
				sumO.incr(v)
				Obs.onClean !-> sumO.incr(-v)
			
		Form.condition (values) ->
			total = null
			for k,v of values.for
				if v is true
					return # we're good
				if !total?
					total = 0
				total += v
			if !total?
				return tr("Select participants")
			if total != values.total
				return tr("Totals do not match")
			
		Plugin.users.iterate (user) !->
			Ui.item !->
				Ui.avatar Plugin.userAvatar(user.key())
				amount = forO.get(user.key())
				Dom.style fontWeight: if amount then 'bold' else ''
				Dom.div !->
					Dom.style
						Flex: true
					Dom.text Plugin.userName(user.key())
				
				if amount
					if amount is true
						amount = (totalO.get() - sumO.get()) / divideO.get()
					Dom.div !->
						Dom.style fontSize: '90%'
						Dom.text formatMoney(amount)
				
				Dom.onTap
					cb: !->
						forO.set user.key(), if amount? then null else true
					longTap: !->
						Modal.prompt tr("Amount payed for %1?", formatName(user.key())), (v) !->
							forO.set user.key(), +v
								
	Dom.div !->
		Dom.style
			textAlign: 'center'
			fontStyle: 'italic'
			padding: '3px'
			color: '#aaa'
			fontSize: '85%'
		Dom.text tr("Hint: long-tap on a user to set a specific amount")

	Form.setPageSubmit (values) !->
		Page.up()
		Server.call 'transaction', editId, values
	
renderSettlePane = (settleO) !->		
	Ui.list !->
		Dom.h2 "Settle"
		Dom.div !->
			Dom.style
				Flex: true
				margin: '4px 0'
				background: '#888'
				color: '#fff'
				fontSize: '80%'
				padding: '4px'
				fontStyle: 'italic'
				
			if account = Db.shared.get('accounts', Plugin.userId())
				Dom.text tr("Your account number: %1", account)
			else	
				Dom.text tr("Tap to setup your account number.")
			Dom.onTap !->
				Modal.prompt tr("Your account number"), (text) !->
					Server.sync 'account', text, !->
						Db.shared.set 'account', Plugin.userId(), text
								
		settleO.iterate (tx) !->
			Ui.item !->
				[from,to] = tx.key().split(':')
				done = tx.get('done')
				amount = tx.get('amount')
				Icon.render
					data: 'good2'
					color: if done&2 then '#080' else if done&1 then '#777' else '#ccc'
					style: {marginRight: '6px'}
				Dom.div !->
					if done&2
						Dom.text tr("%1 received %2 from %3", formatName(to,true), formatMoney(amount), formatName(from))
					else
						if done&1
							Dom.text tr("%1 payed %2 to %3", formatName(from,true), formatMoney(amount), formatName(to))
						else
							Dom.span !->
								Dom.style
									fontWeight: if +from is Plugin.userId() then 'bold' else ''
								Dom.text tr("%1 should pay %2 to %3", formatName(from,true), formatMoney(amount), formatName(to))
					
						Dom.div !->
							Dom.style
								fontSize: '80%'
								fontWeight: if +to is Plugin.userId() then 'bold' else ''
								
							if +to is Plugin.userId()
								Dom.text tr("Tap to confirm receipt of payment")
							else if done&1
								Dom.text tr("Waiting for %1 to confirm payment", formatName(to))
							else if account = Db.shared.get('accounts', to)
								Dom.text tr("Account: %1", account)
							else
								Dom.text tr("%1 has not entered account info", formatName(to))
							
				if +from is Plugin.userId() and !(done&2)
					Dom.onTap !->
						Server.sync 'settlePayed', tx.key(), !->
							tx.set 'done', (done&~1) | ((done^1)&1)
					
				else if +to is Plugin.userId()
					Dom.onTap !->
						Server.sync 'settleDone', tx.key(), !->
							tx.set 'done', (done&~2) | ((done^2)&2)

		if Plugin.userIsAdmin()
			Dom.div !->
				Dom.style textAlign: 'right'
				complete = true
				for k,v of settleO.get()
					if !(v.done&2)
						complete = false
						break
			
				buttonText = if complete then tr("Finish") else tr("Cancel")
				if complete
					Ui.button tr("Finish"), !->
						require('modal').confirm tr("Finish settle?"), tr("The pane will be discarded for all members."), !->
							Server.call 'settleStop'
				else
					Ui.button tr("Cancel"), !->
						require('modal').confirm tr("Cancel settle?"), tr("There are uncompleted settling transactions! When someone has payed without acknowledge of the recipient, balances might be inaccurate..."), !->
							Server.call 'settleStop'
		

formatMoney = (amount) ->
	"E "+Math.floor(amount)+"."+('0'+(Math.round(amount*100)%100))[-2..]
	
formatName = (userId, capitalize) ->
	if +userId != Plugin.userId()
		Plugin.userName(userId)
	else if capitalize
		tr("You")
	else
		tr("you")
		
formatGroup = (userIds, capitalize) ->
	if userIds.length > 3
		userIds[0...3].map(formatName).join(', ') + ' and ' + (userIds.length-3) + ' others'
	else if userIds.length > 1
		userIds[0...userIds.length-1].map(formatName).join(', ') + ' and ' + Plugin.userName(userIds[userIds.length-1])
	else if userIds.length is 1
		formatName(userIds[0], capitalize)

selectUser = (cb) !->
	require('modal').show tr("Select user"), !->
	    Dom.style width: '80%'
	    Dom.div !->
	        Dom.style
	            maxHeight: '40%'
	            backgroundColor: '#eee'
	            margin: '-12px'
	        Dom.overflow()
	        Plugin.users.iterate (user) !->
	            Ui.item !->
	                Ui.avatar user.get('avatar')
	                Dom.text user.get('name')
	                Dom.onTap !->
	                    cb user.key()
	                    Modal.remove()
	        , (user) ->
	            +user.key()
	, false, ['cancel', tr("Cancel")]
	
		
Dom.css
	'.selected:not(.tap)':
		background: '#f0f0f0'
