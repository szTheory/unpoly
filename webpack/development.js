let webpack = require('webpack')
let { merge, file, scriptPipeline, minify } = require('./shared.js')


module.exports = [
  { ...file('./lib/assets/javascripts/unpoly.js', 'unpoly.development.es5.js'),
    ...scriptPipeline('ES5'),
    ...minify(false),
  },

  { ...file('./lib/assets/javascripts/unpoly.js', 'unpoly.development.esnext.js'),
    ...scriptPipeline('ESNext'),
    ...minify(false),
  },

  merge(
    file('./spec/specs.js', 'specs.js'),
    scriptPipeline('ES5'),
    minify(false)
  ),

  merge(
    file('./spec/jasmine.js', 'jasmine.js'),
    scriptPipeline('ES5'),
    minify(false),
    { node: { fs: 'empty' }, // fix "Error: Can't resolve 'fs'
      plugins: [new webpack.ProvidePlugin({
        jasmineRequire: 'jasmine-core/lib/jasmine-core/jasmine.js',
        getJasmineRequireObj: [__dirname + '/get_jasmine_require_obj.js', 'default'],
      })]
    }
  )
]