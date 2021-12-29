library google_places_flutter;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_places_flutter/model/place_details.dart';
import 'package:google_places_flutter/model/prediction.dart';

import 'package:rxdart/subjects.dart';
import 'package:dio/dio.dart';
import 'package:rxdart/rxdart.dart';

class GooglePlaceAutoCompleteTextField extends StatefulWidget {
  InputDecoration inputDecoration;
  ItemClick? itmClick;
  GetPlaceDetailswWithLatLng? getPlaceDetailWithLatLng;
  bool isLatLngRequired = true;

  TextStyle textStyle;
  String? googleAPIKey;
  int debounceTime = 600;
  List<String>? countries = [];
  TextEditingController textEditingController = TextEditingController();

  String? proxy;
  String? googleProxy;
  Map<String,dynamic>? headers;

  GooglePlaceAutoCompleteTextField(
      {required this.textEditingController,
      this.googleAPIKey,
      this.proxy,
      this.googleProxy,
      this.headers,
      this.debounceTime: 600,
      this.inputDecoration: const InputDecoration(),
      this.itmClick,
      this.isLatLngRequired=true,
      this.textStyle: const TextStyle(),
      this.countries,
      this.getPlaceDetailWithLatLng,
      });

  @override
  _GooglePlaceAutoCompleteTextFieldState createState() =>
      _GooglePlaceAutoCompleteTextFieldState();
}

class _GooglePlaceAutoCompleteTextFieldState
    extends State<GooglePlaceAutoCompleteTextField> {
  final subject = new PublishSubject<String>();
  OverlayEntry? _overlayEntry;
  List<Prediction> alPredictions = [];

  TextEditingController controller = TextEditingController();
  final LayerLink _layerLink = LayerLink();
  bool isSearched = false;

  bool useGoogle = false;

  FocusNode _focusNode = new FocusNode();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        decoration: widget.inputDecoration,
        style: widget.textStyle,
        focusNode: _focusNode,
        controller: widget.textEditingController,
        onChanged: (string) => (subject.add(string)),
      ),
    );
  }

  getLocation(String text) async {
    Dio dio = new Dio();
    if(widget.proxy == null){
      return;
    }
    late PlacesAutocompleteResponse subscriptionResponse;
    if(!useGoogle){
      String googleUrl = widget.proxy!+"https://atlas.microsoft.com/search/address/json?api-version=1.0&language=en-US&query=$text";
      try{
        googleUrl = googleUrl +"&lat="+widget.headers!["lat"]+"&lon="+widget.headers!["lng"];
      }catch(_){
        print(_);
      }
      Response googleResponse = await dio.get(googleUrl);
      subscriptionResponse =
      PlacesAutocompleteResponse.fromJson(googleResponse.data);
    }else {
      String url = widget.googleProxy! +
          "https://maps.googleapis.com/maps/api/geocode/json?address=$text";
      try {
        url = url + "&lat=" + widget.headers!["lat"] + "&lng=" +
            widget.headers!["lng"];
      } catch (_) {
        print(_);
      }
      Response response = await dio.get(url);
      subscriptionResponse =
      PlacesAutocompleteResponse.fromJson(response.data);
    }
    if (text.length == 0) {
      alPredictions.clear();
      if(this._overlayEntry != null) {
        this._overlayEntry!.remove();
      }
      return;
    }

    isSearched = false;
    if (subscriptionResponse.predictions!.length > 0) {
      alPredictions.clear();
      alPredictions.addAll(subscriptionResponse.predictions!);
    }

    if(this._overlayEntry != null){
      this._overlayEntry!.remove();
    }
    this._overlayEntry = null;
    this._overlayEntry = this._createOverlayEntry();
    Overlay.of(context)!.insert(this._overlayEntry!);
    this._overlayEntry!.markNeedsBuild();
  }

  @override
  void initState() {
    subject.stream
        .distinct()
        .debounceTime(Duration(milliseconds: widget.debounceTime))
        .listen(textChanged);
    _focusNode.addListener(() {
      if(_focusNode.hasFocus){
        textChanged(widget.textEditingController.text);
      }
    });
  }

  textChanged(String text) async {
    useGoogle = false;
    getLocation(text);
  }

  OverlayEntry? _createOverlayEntry() {
    if (context != null && context.findRenderObject() != null) {
      RenderBox renderBox = context.findRenderObject() as RenderBox;
      var size = renderBox.size;
      var offset = renderBox.localToGlobal(Offset.zero);
      return OverlayEntry(
          builder: (context) => Positioned(
                left: offset.dx,
                top: size.height + offset.dy,
                width: size.width,
                child: CompositedTransformFollower(
                  showWhenUnlinked: false,
                  link: this._layerLink,
                  offset: Offset(0.0, size.height + 5.0),
                  child: Material(
                      clipBehavior: Clip.antiAlias,
                      elevation: 1.0,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: (alPredictions.length>=7?6:alPredictions.length)+(useGoogle||widget.textEditingController.text != ""?0:1),
                        itemBuilder: (BuildContext context, int index) {
                          if(!useGoogle && index == (alPredictions.length>=7?6:alPredictions.length)+(useGoogle||widget.textEditingController.text != ""?0:1) - 1){
                            return InkWell(onTap:(){
                              setState(() {
                                useGoogle = true;
                                getLocation(widget.textEditingController.text);
                              });
                            },child:  Container(
                                padding: EdgeInsets.all(10),
                                child: Text("Show more options",style: TextStyle(color: Colors.blue),)),);
                          }
                          return InkWell(
                            onTap: () {
                              print("Rebuilding");
                              FocusScope.of(context).requestFocus(new FocusNode());
                              if (index < alPredictions.length) {
                                widget.itmClick!(alPredictions[index]);
                                if (!widget.isLatLngRequired) return;
                                getPlaceDetailsFromPlaceId(
                                    alPredictions[index]);
                              }
                              removeOverlay();
                            },
                            child: Container(
                                padding: EdgeInsets.all(10),
                                child: Text(alPredictions[index].formattedAddress??alPredictions[index].description??"")),
                          );
                        },
                      )),
                ),
              ));
    }
  }

  removeOverlay() {
    alPredictions.clear();
    if(this._overlayEntry != null){
      this._overlayEntry!.remove();
      this._overlayEntry = null;
    }
  }



  Future<Response?> getPlaceDetailsFromPlaceId(Prediction prediction) async {
    //String key = GlobalConfiguration().getString('google_maps_key');

    // String url =
    //     "https://maps.googleapis.com/maps/api/place/details/json?placeid=${prediction.placeId}";
    // if(widget.googleAPIKey != null) {
    //   url +="&key=${widget
    //       .googleAPIKey}";
    // }else if(widget.proxy != null){
    //   url = widget.proxy + url;
    // }
    // try{
    //   url = url +"&lat="+widget.headers["lat"]+"&lng="+widget.headers["lng"]+"&radius=5000";
    // }catch(_){
    //   print(_);
    // }
    // Response response = await Dio().get(
    //   url,
    // );
    //
    // PlaceDetails placeDetails = PlaceDetails.fromJson(response.data);
    // print(placeDetails.result.formattedAddress);
    // prediction.formattedAddress = placeDetails.result.formattedAddress;
    // prediction.lat = placeDetails.result.geometry.location.lat.toString();
    // prediction.lng = placeDetails.result.geometry.location.lng.toString();

    widget.getPlaceDetailWithLatLng!(prediction);

//    prediction.latLng = new LatLng(
//        placeDetails.result.geometry.location.lat,
//        placeDetails.result.geometry.location.lng);
  }
}

PlacesAutocompleteResponse parseResponse(Map responseBody) {
  return PlacesAutocompleteResponse.fromJson(responseBody as Map<String, dynamic>);
}

PlaceDetails parsePlaceDetailMap(Map responseBody) {
  return PlaceDetails.fromJson(responseBody as Map<String, dynamic>);
}

typedef ItemClick = void Function(Prediction postalCodeResponse);
typedef GetPlaceDetailswWithLatLng = void Function(
    Prediction postalCodeResponse);
