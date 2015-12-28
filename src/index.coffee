# Description
#
# Session connects users with shell scripts.
# Author: howethomas, ctbailey
#
Stream = require('stream')
Pipe = require('multipipe')
Util = require('util')
{EventEmitter} = require('events')

DEBUG = true
debug = (text) ->
  console.log text if DEBUG

Watson = require('watson-developer-cloud')
if process.env.WATSON_USERNAME? and process.env.WATSON_PASSWORD?
  LanguageTranslation = Watson.language_translation(
    username: process.env.WATSON_USERNAME
    password: process.env.WATSON_PASSWORD
    version: 'v2'
    )

class LanguageDetector extends Stream.Transform
  constructor: (@lang, @adaptive, @detectorId) ->
    @detectorId ?= 'Language Detector'
    @debug = (text) -> debug "[#{@detectorId}] " + text
    @words = ''
    super
    @debug "Adaptive value in constructor: #{@adaptive}"
    if @lang
      @debug "Detector contstructed with #{@lang}"
    else
      @debug "Detector constructed in adaptive mode"

  bestLangGuess : (currentLang, bestGuess, secondGuess) ->
    debug "Best guess: #{bestGuess.language}: #{bestGuess.confidence}"
    debug "Second guess: #{secondGuess.language}: #{secondGuess.confidence}"
    return currentLang if bestGuess.language is currentLang
    # If the best guess is twice the current guess, choose it.
    # Otherwise, keep the status quo.
    if bestGuess.confidence > (2 * secondGuess.confidence)
      return bestGuess.language
    currentLang


  analyze: (words, cb) =>
    @debug "Adaptive value in analyze: #{@adaptive}"
    @debug "Running in adaptive mode " if @adaptive
    if @adaptive
      @words += words
      @debug "Analyzing " + Util.inspect @words
      LanguageTranslation.identify text: @words, (err, result) =>
        if (err)
          @debug "Language detection error : " + err
        else
          # Debounce this. If the another language is twice as likely
          # as the one we are using, switch it.
          bestGuess = result.languages[0]
          secondGuess = result.languages[1]
          newLang = @bestLangGuess @lang, bestGuess, secondGuess
          if @lang isnt newLang
            @debug "language change: Old: #{@lang}, New: #{newLang}"
            @emit 'langChanged', @lang, newLang
          @lang = newLang
          # TODO: Check to see if @lang a supported translation.
          @debug "Language detected as " + @lang
        cb()
    else
      cb()

  getLang: () =>
    @debug "Language detector thinks language is #{@lang}"
    @lang

  _transform: (chunk, enc, cb) =>
    @debug "About to analyze"
    @analyze chunk.toString(), () =>
      @debug "Done analyzing"
      @push chunk
      cb()

class LanguageStream extends Stream.Transform
  constructor: (@fromLanguage, @toLanguage) ->
    super

  _transform: (chunk, enc, cb) =>
    words = chunk.toString()
    debug "Translating #{words.trim()}"
    from = @fromLanguage()
    to = @toLanguage()

    unknownLanguage = not from or not to
    sameLanguage = from is to
    # if we don't know the source or target languages
    # don't translate anythhing. This is the case
    # if we're in adaptive language detection mode
    # and the user hasn't said anything yet.
    if unknownLanguage or sameLanguage
      debug "Not translating: we don't know the from lang" if not from
      debug "Not translating: we don't know the to lang" if not to
      debug "Not translating: src and target langs are the same" if sameLanguage
      @push chunk
      cb()
      return

    options =
      text: words
      source: from
      target: to
    LanguageTranslation.translate options, (err, result) =>
      if (err)
        debug "Watson translation error :  " + Util.inspect err
        debug "Translation run with #{Util.inspect options}"
        @push chunk
      else
        trans = result.translations[0].translation
        trans += '\n' unless trans.slice(-1) is '\n'
        debug "Original : #{words}"
        debug "Trans: #{Util.inspect trans}"
        buffTrans = new Buffer trans
        debug "Trans: #{Util.inspect buffTrans}"
        debug "Trans: #{Util.inspect chunk}"
        @push buffTrans
      cb()
      return

class LanguageFilter extends EventEmitter
  constructor: (@nearEndLanguage, @farEndLanguage, @adaptive) ->
    @adaptive ?= true
    nearEndDetector = new LanguageDetector( @nearEndLanguage,
                                            @adaptive,
                                            "Near End")
    farEndDetector = new LanguageDetector(  @farEndLanguage,
                                            @adaptive,
                                            "Far End")
    ingressLangStream = new LanguageStream  farEndDetector.getLang,
                                            nearEndDetector.getLang
    egressLangStream = new LanguageStream  nearEndDetector.getLang,
                                           farEndDetector.getLang
    @ingressStream = Pipe(farEndDetector, ingressLangStream)
    @egressStream = Pipe(nearEndDetector, egressLangStream)
    farEndDetector.on 'langChanged', (oldLang, newLang) =>
      debug "Language change event : #{oldLang} to #{newLang}"
      @emit 'langChanged', oldLang, newLang

module.exports = LanguageFilter
