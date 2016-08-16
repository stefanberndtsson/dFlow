import Ember from 'ember';
import InViewportMixin from 'd-flow-ember/mixins/in-view-port';

export default Ember.Component.extend(InViewportMixin, {
  session: Ember.inject.service(),
  store: Ember.inject.service(),
  init() {
    var that = this;
    var token =  this.get('session.data.authenticated.token');
    if (this.get('imagesFolderPath') && this.get('imagesSource')){
    this.store.find('thumbnail', '?source_dir=' + this.get('imagesFolderPath') + '&source=' + this.get('imagesSource')+ '&image=' + this.get('image.num') + '&token=' + token).then(function(response){
      that.set('small', response.thumbnail);
    });
    } else {
      console.log('imagesFoldePath or imagesSource not given, not fetching thumbnails');
    }
    this._super();
  },
  tagName: 'div',
  classNames: ['col-sm-6'],

  mouseEnter: function(){
    this.set('activeFrame', true);
  },
  mouseLeave: function(){
    this.set('activeFrame', false);
  },

  actions: {
    setPhysical: function(page_type){
      this.set('image.page_type', page_type);
    },
    setLogical: function(page_content){
      this.set('image.page_content', page_content);
    }
  }
});