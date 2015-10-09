Adventure = angular.module "Adventure"

## CONTROLLER ##
Adventure.controller 'AdventureController', ($scope, $rootScope, legacyQsetSrv) ->

	$scope.BLANK = "blank"
	$scope.MC = "mc"
	$scope.SHORTANS = "shortanswer"
	$scope.HOTSPOT = "hotspot"
	$scope.TRANS = "transitional"
	$scope.NARR = "narrative" # May not be required
	$scope.END = "end" # May not be required
	$scope.OVER = "over" # the imaginary node after end nodes, representing the end of the widget

	# TODO Are these really required?
	PADDING_LEFT = 20
	PADDING_TOP = 15
	CONTAINER_WIDTH = 730
	CONTAINER_HEGIHT = 650

	$scope.title = ""
	$scope.qset = null

	$scope.engine =
		start: (instance, qset, version = '1') ->

			#Convert an old qset prior to running the widget
			if parseInt(version) is 1 then qset = JSON.parse legacyQsetSrv.convertOldQset qset

			$scope.$apply ->
				$scope.title = instance.name
				$scope.qset = qset
				manageQuestionScreen(qset.items[0].options.id)
		manualResize: true

	$scope.questionFormat =
		fontSize: 22
		height: 220

	# Object containing properties for the hotspot label that appears on mouseover
	$scope.hotspotLabelTarget =
		text: null
		x: null
		y: null
		show: false

	# Update the screen depending on the question type (narrative, mc, short answer, hotspot, etc)
	manageQuestionScreen = (questionId) ->

		# Acquire question data based on question id
		for n in [0...$scope.qset.items.length]
			if $scope.qset.items[n].options.id is questionId
				q_data = $scope.qset.items[n]

		unless q_data.options.asset then $scope.layout = "text-only"
		else $scope.layout = q_data.options.asset.align

		$scope.question =
			text : q_data.questions[0].text, # questions MUST be an array, always 1 index w/ single text property
			layout: $scope.layout,
			type : q_data.options.type,
			id : q_data.options.id
			materiaId: q_data.id
			options: q_data.options

		$scope.answers = []

		if q_data.answers
			for i in [0..q_data.answers.length-1]
				continue if not q_data.answers[i]

				answer =
					text : q_data.answers[i].text
					link : q_data.answers[i].options.link
					index : i
					options : q_data.answers[i].options
				$scope.answers.push answer

		$scope.q_data = q_data

		# TODO Add back in with Layout support
		# check if question has an associated asset (for now, just an image)
		# if $scope.question.type is $scope.HOTSPOT then $scope.question.layout = LAYOUT_VERT_TEXT
		if $scope.question.type is $scope.HOTSPOT then $scope.layout = "hotspot"
		if $scope.question.layout isnt "text-only"
			image_url = Materia.Engine.getImageAssetUrl q_data.options.asset.id
			$scope.question.image = image_url

		switch q_data.options.type
			when $scope.OVER then _end() # Creator doesn't pass a value like this back yet / technically this shouldn't be called - the end call is made is _handleAnswerSelection
			when $scope.NARR, $scope.END then handleTransitional q_data
			when $scope.MC then handleMultipleChoice q_data
			when $scope.HOTSPOT then handleHotspot q_data
			when $scope.SHORTANS then handleShortAnswer q_data
			else
				handleEmptyNode() # Should hopefully only happen on preview, when empty nodes are allowed

	# Handles selection of MC answer choices and transitional buttons (narrative and end screen)
	$scope.handleAnswerSelection = (link, index) ->
		# link to -1 indicates the widget should advance to the score screen
		if link is -1 then return _end()

		$scope.selectedAnswer = $scope.q_data.answers[index].text

		# Disable the hotspot label before moving on, if it's a hotspot
		if $scope.type is $scope.HOTSPOT
			$scope.hotspotLabelTarget.show = false
			$scope.hotspotLabelTarget.x = null
			$scope.hotspotLabelTarget.y = null

		# record the answer
		_logProgress()

		if $scope.q_data.answers[index].options.feedback
			$scope.feedback = $scope.q_data.answers[index].options.feedback
			$scope.next = link
		else
			manageQuestionScreen link

	# Do stuff when the user submits something in the SA answer box
	$scope.handleShortAnswerInput = ->

		response = $scope.response.toLowerCase()
		$scope.response = ""

		# Outer loop - loop through every answer set (index 0 is always [All Other Answers] )
		for i in [0...$scope.q_data.answers.length]

			# If it's the default, catch-all answer, then skip
			if $scope.q_data.answers[i].options.isDefault then continue

			# Loop through each match to see if it matches the recorded response
			for j in [0...$scope.q_data.answers[i].options.matches.length]

				# TODO make matching algo more robust
				if $scope.q_data.answers[i].options.matches[j].toLowerCase().trim() is response

					link = ~~$scope.q_data.answers[i].options.link # is parsing required?

					$scope.selectedAnswer = $scope.q_data.answers[i].options.matches[j]
					console.log $scope.selectedAnswer
					_logProgress()

					if $scope.q_data.answers[i].options and $scope.q_data.answers[i].options.feedback
						$scope.feedback = $scope.q_data.answers[i].options.feedback
						$scope.next = link
					else
						manageQuestionScreen link

					return true

		# Fallback in case the user response doesn't match anything. Have to match the link associated with [All Other Answers]
		for answer in $scope.q_data.answers
			if answer.options.isDefault

				$scope.selectedAnswer = response
				_logProgress() # Log the response

				link = ~~answer.options.link
				if answer.options.feedback
					$scope.feedback = answer.options.feedback
					$scope.next = link
				else
					manageQuestionScreen link

				return false

	$scope.closeFeedback = ->
		$scope.feedback = ""
		manageQuestionScreen $scope.next

	handleMultipleChoice = (q_data) ->
		$scope.type = $scope.MC


	# Filter function called by ng-repeat to order answers randomly (or not)
	$scope.mcAnswerOrdering = (answer) ->
		if $scope.q_data.options.randomize
			return Math.random()
		else
			return $scope.answers.indexOf answer


	handleHotspot = (q_data) ->
		$scope.type = $scope.HOTSPOT
		$scope.question.layout = 1

		$scope.question.options.hotspotColor = 7772386 if not $scope.question.options.hotspotColor
		$scope.question.options.hotspotColor = '#' + ('000000' + $scope.question.options.hotspotColor.toString(16)).substr(-6)

		img = new Image()
		img.src = $scope.question.image

		img.onload = ->
			# if it's an old QSet, the hotspot has to be scaled once the image is loaded
			# The old hotspot coordinate system scales the hotspot points based on original image size, so can't do this step earlier
			if $scope.q_data.options.legacyScaleMode
				legacyQsetSrv.handleLegacyScale $scope.answers, img
				$scope.$apply()

				# This doesn't change the saved QSet, but it prevents the scaling from being applied twice if you come back to this node.
				delete $scope.q_data.options.legacyScaleMode

	handleShortAnswer = (q_data) ->
		$scope.type = $scope.SHORTANS
		$scope.response = ""

	# Transitional questions are the ones that don't require answers - i.e., narrative and end node
	handleTransitional = (q_data) ->
		# Set the link based on the node type - for end screens, the link is -1 (score screen) and submit the final score
		link = null
		if $scope.question.type is $scope.END
			link = -1
			Materia.Score.submitFinalScoreFromClient q_data.id, $scope.question.text, q_data.options.finalScore
		else
			link = q_data.answers[0].options.link

		$scope.link = link
		$scope.type = $scope.TRANS

	handleEmptyNode = (q_data) ->
		$scope.type = $scope.TRANS
		$scope.layout = "text-only"
		$scope.question.text = "[Blank destination: click Continue to end the widget preview.]"
		$scope.link = -1
		Materia.Score.submitFinalScoreFromClient q_data.id, $scope.question.text, 100

	# Submit the user's response to the logs
	_logProgress = ->

		if $scope.selectedAnswer isnt null # TODO is this check required??
			Materia.Score.submitQuestionForScoring $scope.question.materiaId, $scope.selectedAnswer

	_end = ->
		Materia.Engine.end yes

	# Kinda hackish, since both autoTextScale and dynamicScale directives update the "style" attribute,
	# need to combine updated properties from both so they don't overwrite each other.
	# If the node isn't MC, just return fontSize, height isn't used
	$scope.formatQuestionStyles = ->

		if $scope.question.type is $scope.MC
			return "font-size:" + $scope.questionFormat.fontSize + "px; height:" + $scope.questionFormat.height + "px;"
		else return "font-size:" + $scope.questionFormat.fontSize + "px;"

	Materia.Engine.start($scope.engine)

## DIRECTIVES ##
Adventure.directive('ngEnter', ->
	return (scope, element, attrs) ->
		element.bind("keypress", (event) ->
			if(event.which == 13 or event.which == 10)
				event.target.blur()
				event.preventDefault()
				scope.$apply ->
					scope.$eval(attrs.ngEnter)
		)
)

# Font will progressively step down from 22px to 12px depending on question length after a threshold is reached
Adventure.directive "autoTextScale", () ->
	restrict: "A",
	link: ($scope, $element, $attrs) ->

		scaleFactor = 100
		scaleThreshold = 200

		style = ""

		$scope.$watch "question", (newVal, oldVal) ->

			if newVal

				text = $element.text()

				if angular.element($element[0]).hasClass("right") or angular.element($element).hasClass("left")
					scaleFactor = 25
					scaleThreshold = 180

				else if angular.element($element[0]).hasClass("top") or angular.element($element).hasClass("bottom")
					scaleFactor = 10
					scaleThreshold = 140

				else
					scaleFactor = 100
					scaleThreshold = 200

				$scope.questionFormat.fontSize = 22 # default font size

				if text.length > scaleThreshold
					diff = (text.length - scaleThreshold) / scaleFactor
					$scope.questionFormat.fontSize -= diff

					if $scope.questionFormat.fontSize < 12 then $scope.questionFormat.fontSize = 12

				$attrs.$set "style", $scope.formatQuestionStyles()

# Scales the height of the question box dynamically based on the height of the answer box
# Ensures the negative space is effectively filled up with question text
# Only used for MC, since MC is the only node type with variable answer container heights
Adventure.directive "dynamicScale", () ->
	restrict: "A",
	link: ($scope, $element, $attrs) ->

		minHeight = 220
		maxHeight = 400

		style = ""

		$scope.$watch "question", (newVal, oldVal) ->
			# answer div:
				# min: 94
				# max: 250

			# question div:
				# min: 220
				# max: 400

			answersHeight = angular.element(".answers")[0].offsetHeight

			diff = 250 - answersHeight

			if (diff + minHeight) < 400 then $scope.questionFormat.height = diff + minHeight
			else $scope.questionFormat.height = 400

			$attrs.$set "style", $scope.formatQuestionStyles()

# Handles the visibility of individual hotspots
Adventure.directive "visibilityManager", () ->
	restrict: "A",
	link: ($scope, $element, $attrs) ->

		$scope.$watch "question", (newVal, oldVal) ->

			if $scope.question.type is $scope.HOTSPOT
				$element.removeAttr "style"

				switch $scope.q_data.options.visibility
					when "mouseover"
						style = "opacity: 0"
						$attrs.$set "style", style

						$element.bind "mouseover", (evt) ->
							$element.removeAttr "style"
							$element.unbind "mouseover"

					when "never"
						style = "opacity: 0"
						$attrs.$set "style", style

Adventure.directive "labelManager", ($timeout) ->
	restrict: "A",
	link: ($scope, $element, $attrs) ->

		# reference to hotspot div element (required for proper X/Y offset)
		hotspotDivReference = angular.element($element).parent().parent()
		# reference to label element (need to find width for proper X offset)
		hotspotLabelReference = angular.element(document.getElementById("hotspot-label"))

		$scope.onHotspotHover = (answer, evt) ->

			if answer.text.length > 0 then $scope.hotspotLabelTarget.text = answer.text
			else return false

			container = document.getElementById "body"

			svgBounds = angular.element($element)[0].getBoundingClientRect()

			# Position the hotspot label just below the hotspot
			$scope.hotspotLabelTarget.x = (svgBounds.left + (svgBounds.width/2)) - hotspotDivReference[0].getBoundingClientRect().left
			$scope.hotspotLabelTarget.y = (svgBounds.bottom + 5) - hotspotDivReference[0].getBoundingClientRect().top

			# Need a timeout so the text is rendered within the label
			# Once its rendered, we offset the X position by half the width so its centered
			# We also check to see if label is clipped by lower edge of iframe, if so move it so it's above the hotspot
			$timeout ->
				labelWidthOffset = hotspotLabelReference[0].getBoundingClientRect().width /2
				$scope.hotspotLabelTarget.x -= labelWidthOffset

				if hotspotLabelReference[0].getBoundingClientRect().bottom > container.offsetHeight
					$scope.hotspotLabelTarget.y = (svgBounds.top + 5) - hotspotLabelReference[0].getBoundingClientRect().height - hotspotDivReference[0].getBoundingClientRect().top

				$scope.hotspotLabelTarget.show = true

		$scope.onHotspotHoverOut = (evt) ->
			$scope.hotspotLabelTarget.show = false
			$scope.hotspotLabelTarget.x = null
			$scope.hotspotLabelTarget.y = null




