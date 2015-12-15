# Description
#
# Session connects users with shell scripts.
# Author: howethomas, ctbailey
#
Stream = require('stream')
Pipe = require('multipipe')
Util = require('util')

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
  constructor: (@lang, @detectorId) ->
    @detectorId ?= 'Language Detector'
    @debug = (text) -> debug "[#{@detectorId}] " + text
    @adaptive = !@lang
    @words = ''
    super
    @debug "Adaptive value in constructor: #{@adaptive}"
    if @lang
      @debug "Detector contstructed with #{@lang}"
    else
      @debug "Detector constructed in adaptive mode"

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
          @lang = result.languages[0].language
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

class LanguageFilter
  constructor: (@nearEndLanguage, @farEndLanguage) ->
    nearEndDetector = new LanguageDetector(@nearEndLanguage, "Near End")
    farEndDetector = new LanguageDetector(@farEndLanguage, "Far End")
    ingressLangStream = new LanguageStream  farEndDetector.getLang,
                                            nearEndDetector.getLang
    egressLangStream = new LanguageStream  nearEndDetector.getLang,
                                           farEndDetector.getLang
    @ingressStream = Pipe(farEndDetector, ingressLangStream)
    @egressStream = Pipe(nearEndDetector, egressLangStream)

module.exports = LanguageFilter
