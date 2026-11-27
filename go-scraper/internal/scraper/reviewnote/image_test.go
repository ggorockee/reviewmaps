package reviewnote

import "testing"

func TestImageURL(t *testing.T) {
	cases := map[string]string{
		"campaigns/eab9e7c0-bcd9-4dcf-af74-c23d930e349f": "https://firebasestorage.googleapis.com/v0/b/reviewnote-e92d9.appspot.com/o/campaigns%2Feab9e7c0-bcd9-4dcf-af74-c23d930e349f?alt=media",
		"items/a b": "https://firebasestorage.googleapis.com/v0/b/reviewnote-e92d9.appspot.com/o/items%2Fa%20b?alt=media",
	}
	for key, want := range cases {
		if got := imageURL(key); got != want {
			t.Errorf("imageURL(%q)\n got %s\nwant %s", key, got, want)
		}
	}
}
